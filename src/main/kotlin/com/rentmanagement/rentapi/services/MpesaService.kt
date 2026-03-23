package com.rentmanagement.rentapi.services

import com.fasterxml.jackson.databind.ObjectMapper
import com.rentmanagement.rentapi.models.PlatformTransaction
import com.rentmanagement.rentapi.repository.*
import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.time.LocalDateTime
import java.util.*

@Service
class MpesaService(
    private val unitRepository: UnitRepository,
    private val tenancyRepository: TenancyRepository,
    private val userRepository: UserRepository,
    private val subscriptionRepository: SubscriptionRepository,
    private val subscriptionPlanRepository: SubscriptionPlanRepository,
    private val platformTransactionRepository: PlatformTransactionRepository,
    private val stkRequestRepository: StkRequestRepository,
    private val jdbcTemplate: JdbcTemplate,
    private val mpesaStkService: MpesaStkService
) {

    private val log = LoggerFactory.getLogger(MpesaService::class.java)
    private val objectMapper = ObjectMapper()

    // =========================================================
    // 🔥 STK INIT (SUBSCRIPTION ONLY)
    // =========================================================
    fun initiateStkPush(phone: String, amount: Double, landlordId: String) {
        try {

            val landlordUUID = UUID.fromString(landlordId)

            mpesaStkService.stkPush(
                phone = phone,
                amount = BigDecimal.valueOf(amount),
                landlordId = landlordUUID
            )

            log.info("🔥 STK TRIGGERED → landlord=$landlordUUID amount=$amount")

        } catch (e: Exception) {
            log.error("❌ STK FAILED", e)
            throw e
        }
    }

    // =========================================================
    // 🔵 STK CALLBACK (RENT PAYMENTS)
    // =========================================================
    fun processPaymentCallback(payload: Map<String, Any>) {

        try {

            log.info("🔥 ===== STK CALLBACK START =====")

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *>
                ?: return log.error("❌ Missing stkCallback")

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1

            if (resultCode != 0) {
                log.warn("❌ STK Payment failed → code=$resultCode")
                return
            }

            val items = callback["CallbackMetadata"]
                ?.let { it as? Map<*, *> }
                ?.get("Item") as? List<Map<String, Any>>
                ?: return log.error("❌ Missing metadata")

            var amount: BigDecimal? = null
            var reference: String? = null
            var phone: String? = null
            var accountRaw: String? = null

            for (item in items) {
                when (item["Name"]) {
                    "Amount" -> amount = BigDecimal((item["Value"] as Number).toString())
                    "MpesaReceiptNumber" -> reference = item["Value"].toString()
                    "PhoneNumber" -> phone = item["Value"].toString()
                    "AccountReference" -> accountRaw = item["Value"].toString()
                }
            }

            val safeAmount = amount ?: return log.error("❌ Missing amount")
            val safeReference = reference ?: return log.error("❌ Missing reference")

            val safeAccount = accountRaw
                ?.uppercase()
                ?.replace("\\s".toRegex(), "")
                ?.replace("-", "")
                ?: return log.error("❌ Missing account")

            log.info("💰 STK PAYMENT → amount=$safeAmount ref=$safeReference account=$safeAccount")

            handlePayment(safeReference, safeAmount, phone, safeAccount, payload)

        } catch (e: Exception) {
            log.error("❌ STK CALLBACK FAILED", e)
        }
    }

    // =========================================================
    // 🟢 C2B PAYMENTS (PAYBILL)
    // =========================================================
    fun processC2BPayment(payload: Map<String, Any>) {

        try {

            log.info("🔥 ===== C2B PAYMENT START =====")

            val reference = payload["TransID"]?.toString()
                ?: return log.error("❌ Missing TransID")

            val amount = payload["TransAmount"]?.toString()?.toBigDecimalOrNull()
                ?: return log.error("❌ Missing amount")

            val phone = payload["MSISDN"]?.toString()

            val safeAccount = payload["BillRefNumber"]?.toString()
                ?.uppercase()
                ?.replace("\\s".toRegex(), "")
                ?.replace("-", "")
                ?: return log.error("❌ Missing account")

            log.info("💰 C2B PAYMENT → amount=$amount ref=$reference account=$safeAccount")

            handlePayment(reference, amount, phone, safeAccount, payload)

        } catch (e: Exception) {
            log.error("❌ C2B FAILED", e)
        }
    }

    // =========================================================
    // 💰 CORE PAYMENT ENGINE
    // =========================================================
    private fun handlePayment(
        reference: String,
        amount: BigDecimal,
        phone: String?,
        account: String,
        payload: Map<String, Any>
    ) {

        try {

            // 🔐 IDEMPOTENCY CHECK
            val exists = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM mpesa_transactions WHERE transaction_code = ?",
                Int::class.java,
                reference
            ) ?: 0

            if (exists > 0) {
                log.warn("⚠️ Duplicate ignored → $reference")
                return
            }

            // 💾 STORE RAW TRANSACTION
            jdbcTemplate.update(
                """
                INSERT INTO mpesa_transactions(
                    transaction_code,
                    phone_number,
                    account_reference,
                    amount,
                    raw_payload,
                    processed
                )
                VALUES (?, ?, ?, ?, ?::jsonb, false)
                """.trimIndent(),
                reference,
                phone,
                account,
                amount,
                objectMapper.writeValueAsString(payload)
            )

            log.info("💾 Transaction stored → $reference")

            // 🔍 FIND UNIT
            val unit = unitRepository.findByReferenceNumberIgnoreCase(account)
                ?: return log.error("❌ Unit not found → $account")

            val tenancy = tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)
                ?: return log.error("❌ No active tenancy → unit=${unit.id}")

            log.info("🏠 MATCH → unit=${unit.id} tenancy=${tenancy.id}")

            // ⚙️ CALL DB FUNCTION
            jdbcTemplate.execute(
                "SELECT process_payment(?::uuid, ?::numeric, ?)"
            ) { ps ->
                ps.setObject(1, tenancy.id)
                ps.setBigDecimal(2, amount)
                ps.setString(3, reference)
                ps.execute()
            }

            // ✅ MARK PROCESSED
            jdbcTemplate.update(
                "UPDATE mpesa_transactions SET processed = true WHERE transaction_code = ?",
                reference
            )

            log.info("🎉 PAYMENT SUCCESS → $reference")

        } catch (e: Exception) {
            log.error("❌ HANDLE PAYMENT FAILED → ref=$reference", e)
        }
    }

    // =========================================================
    // 🟢 SUBSCRIPTION CALLBACK (STK ONLY)
    // =========================================================
    fun processSubscriptionCallback(payload: Map<String, Any>) {

        try {

            log.info("🔥 ===== SUBSCRIPTION CALLBACK START =====")

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *>
                ?: return log.error("❌ Missing stkCallback")

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1
            val checkoutId = callback["CheckoutRequestID"]?.toString()

            if (resultCode != 0) {

                log.warn("❌ SUBSCRIPTION FAILED → checkout=$checkoutId")

                checkoutId?.let {
                    stkRequestRepository.findByCheckoutRequestId(it)?.apply {
                        status = "FAILED"
                        stkRequestRepository.save(this)
                    }
                }

                return
            }

            val items = callback["CallbackMetadata"]
                ?.let { it as? Map<*, *> }
                ?.get("Item") as? List<Map<String, Any>>
                ?: return log.error("❌ Missing metadata")

            var amount: BigDecimal? = null
            var reference: String? = null

            for (item in items) {
                when (item["Name"]) {
                    "Amount" -> amount = BigDecimal((item["Value"] as Number).toString())
                    "MpesaReceiptNumber" -> reference = item["Value"].toString()
                }
            }

            val safeAmount = amount ?: return
            val safeReference = reference ?: return
            val safeCheckoutId = checkoutId ?: return

            // 🔐 IDEMPOTENCY
            if (platformTransactionRepository.existsByReference(safeReference)) {
                log.warn("⚠️ Duplicate subscription ignored → $safeReference")
                return
            }

            val stkRequest = stkRequestRepository.findByCheckoutRequestId(safeCheckoutId)
                ?: throw RuntimeException("STK request not found")

            val landlord = userRepository.findById(stkRequest.landlordId).orElseThrow()

            val plan = subscriptionPlanRepository.findMatchingPlan(safeAmount)
                ?: throw RuntimeException("Plan not found for amount=$safeAmount")

            // 💾 SAVE PLATFORM TX
            platformTransactionRepository.save(
                PlatformTransaction(
                    id = UUID.randomUUID(),
                    landlordId = landlord.id!!,
                    amount = safeAmount,
                    reference = safeReference
                )
            )

            // 💰 UPDATE WALLET
            jdbcTemplate.update(
                "UPDATE platform_wallet SET balance = balance + ?",
                safeAmount
            )

            // 🔄 EXPIRE OLD
            jdbcTemplate.update(
                "UPDATE subscriptions SET status = 'EXPIRED' WHERE landlord_id = ? AND status = 'ACTIVE'",
                landlord.id
            )

            // 🆕 CREATE NEW
            val start = LocalDateTime.now()
            val end = start.plusMonths(1)

            jdbcTemplate.update(
                """
                INSERT INTO subscriptions (
                    id,
                    landlord_id,
                    plan_id,
                    start_date,
                    end_date,
                    status
                )
                VALUES (?, ?, ?, ?, ?, 'ACTIVE')
                """.trimIndent(),
                UUID.randomUUID(),
                landlord.id,
                plan.id,
                start,
                end
            )

            // ✅ MARK SUCCESS
            stkRequest.status = "SUCCESS"
            stkRequestRepository.save(stkRequest)

            log.info("🎉 SUBSCRIPTION ACTIVATED → landlord=${landlord.id}")

        } catch (e: Exception) {
            log.error("❌ SUBSCRIPTION CALLBACK FAILED", e)
        }
    }
}