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
    // 🔥 STK INIT
    // =========================================================
    fun initiateStkPush(phone: String, amount: Double, landlordId: String) {

        val landlordUUID = UUID.fromString(landlordId)

        mpesaStkService.stkPush(
            phone = phone,
            amount = BigDecimal.valueOf(amount),
            landlordId = landlordUUID
        )

        log.info("🔥 STK TRIGGERED → landlord=$landlordUUID amount=$amount")
    }

    // =========================================================
    // 🔵 STK CALLBACK (RENT)
    // =========================================================
    fun processPaymentCallback(payload: Map<String, Any>) {

        try {

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *>
                ?: return log.error("❌ Missing stkCallback")

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1

            if (resultCode != 0) {
                log.warn("❌ STK failed → code=$resultCode")
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

            items.forEach {
                when (it["Name"]) {
                    "Amount" -> amount = BigDecimal((it["Value"] as Number).toString())
                    "MpesaReceiptNumber" -> reference = it["Value"].toString()
                    "PhoneNumber" -> phone = it["Value"].toString()
                    "AccountReference" -> accountRaw = it["Value"].toString()
                }
            }

            val safeAmount = amount ?: return log.error("❌ Missing amount")
            val safeReference = reference ?: return log.error("❌ Missing reference")

            val safeAccount = accountRaw
                ?.uppercase()
                ?.replace("\\s".toRegex(), "")
                ?.replace("-", "")
                ?: return log.error("❌ Missing account")

            handlePayment(safeReference, safeAmount, phone, safeAccount, payload)

        } catch (e: Exception) {
            log.error("❌ STK CALLBACK FAILED", e)
        }
    }

    // =========================================================
    // 🟢 C2B PAYMENTS
    // =========================================================
    fun processC2BPayment(payload: Map<String, Any>) {

        try {

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

            handlePayment(reference, amount, phone, safeAccount, payload)

        } catch (e: Exception) {
            log.error("❌ C2B FAILED", e)
        }
    }

    // =========================================================
    // 💰 CORE ENGINE
    // =========================================================
    private fun handlePayment(
        reference: String,
        amount: BigDecimal,
        phone: String?,
        account: String,
        payload: Map<String, Any>
    ) {

        try {

            val exists = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM mpesa_transactions WHERE transaction_code = ?",
                Int::class.java,
                reference
            ) ?: 0

            if (exists > 0) {
                log.warn("⚠️ Duplicate ignored → $reference")
                return
            }

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

            val unit = unitRepository.findByReferenceNumberIgnoreCase(account)
                ?: return log.error("❌ Unit not found → $account")

            val tenancy = tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)
                ?: return log.error("❌ No tenancy → unit=${unit.id}")

            jdbcTemplate.execute(
                "SELECT process_payment(?::uuid, ?::numeric, ?)"
            ) { ps ->
                ps.setObject(1, tenancy.id)
                ps.setBigDecimal(2, amount)
                ps.setString(3, reference)
                ps.execute()
            }

            jdbcTemplate.update(
                "UPDATE mpesa_transactions SET processed = true WHERE transaction_code = ?",
                reference
            )

            log.info("🎉 PAYMENT SUCCESS → $reference")

        } catch (e: Exception) {
            log.error("❌ HANDLE PAYMENT FAILED → $reference", e)
        }
    }

    // =========================================================
    // 🟣 SUBSCRIPTION CALLBACK
    // =========================================================
    fun processSubscriptionCallback(payload: Map<String, Any>) {

        try {

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *>
                ?: return log.error("❌ Missing stkCallback")

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1
            val checkoutId = callback["CheckoutRequestID"]?.toString()
                ?: return log.error("❌ Missing checkoutId")

            if (resultCode != 0) {

                stkRequestRepository.findByCheckoutRequestId(checkoutId)?.apply {
                    status = "FAILED"
                    stkRequestRepository.save(this)
                }

                log.warn("❌ SUBSCRIPTION FAILED → $checkoutId")
                return
            }

            val items = callback["CallbackMetadata"]
                ?.let { it as? Map<*, *> }
                ?.get("Item") as? List<Map<String, Any>>
                ?: return log.error("❌ Missing metadata")

            var amount: BigDecimal? = null
            var reference: String? = null

            items.forEach {
                when (it["Name"]) {
                    "Amount" -> amount = BigDecimal((it["Value"] as Number).toString())
                    "MpesaReceiptNumber" -> reference = it["Value"].toString()
                }
            }

            val safeAmount = amount ?: return log.error("❌ Missing amount")
            val safeReference = reference ?: return log.error("❌ Missing reference")

            // ✅ FIXED PLAN MATCHING (SAFE FOR MONEY)
            val plan = subscriptionPlanRepository.findAll()
                .firstOrNull { it.price.compareTo(safeAmount) == 0 }
                ?: return log.error("❌ No plan for amount=$safeAmount")

            log.info("📦 PLAN MATCHED → ${plan.name} (${plan.price})")

            if (platformTransactionRepository.existsByReference(safeReference)) {
                log.warn("⚠️ Duplicate subscription → $safeReference")
                return
            }

            val stkRequest = stkRequestRepository.findByCheckoutRequestId(checkoutId)
                ?: return log.error("❌ STK request not found")

            val landlord = userRepository.findById(stkRequest.landlordId).orElseThrow()

            platformTransactionRepository.save(
                PlatformTransaction(
                    id = UUID.randomUUID(),
                    landlordId = landlord.id!!,
                    amount = safeAmount,
                    reference = safeReference
                )
            )

            jdbcTemplate.update(
                "UPDATE platform_wallet SET balance = balance + ?",
                safeAmount
            )

            jdbcTemplate.update(
                "UPDATE subscriptions SET status='EXPIRED' WHERE landlord_id=? AND status='ACTIVE'",
                landlord.id
            )

            val start = LocalDateTime.now()
            val end = start.plusMonths(1)

            jdbcTemplate.update(
                """
                INSERT INTO subscriptions (
                    id, landlord_id, plan_id, start_date, end_date, status
                )
                VALUES (?, ?, ?, ?, ?, 'ACTIVE')
                """.trimIndent(),
                UUID.randomUUID(),
                landlord.id,
                plan.id,
                start,
                end
            )

            stkRequest.status = "SUCCESS"
            stkRequestRepository.save(stkRequest)

            log.info("🎉 SUBSCRIPTION ACTIVATED → landlord=${landlord.id}")

        } catch (e: Exception) {
            log.error("❌ SUBSCRIPTION CALLBACK FAILED", e)
        }
    }
}