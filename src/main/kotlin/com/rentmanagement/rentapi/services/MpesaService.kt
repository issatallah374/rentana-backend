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
        try {

            mpesaStkService.stkPush(
                phone = phone,
                amount = BigDecimal(amount),
                landlordId = UUID.fromString(landlordId)
            )

            log.info("🔥 STK TRIGGERED")

        } catch (e: Exception) {
            log.error("❌ STK FAILED", e)
        }
    }

    // =========================================================
    // 🔵 RENT PAYMENTS (🔥 NORMALIZED)
    // =========================================================
    fun processPaymentCallback(payload: Map<String, Any>) {

        try {

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *> ?: return

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1
            if (resultCode != 0) return

            val items = callback["CallbackMetadata"]
                ?.let { it as? Map<*, *> }
                ?.get("Item") as? List<Map<String, Any>> ?: return

            var amount: BigDecimal? = null
            var reference: String? = null
            var phone: String? = null
            var account: String? = null

            for (item in items) {
                when (item["Name"]) {
                    "Amount" -> amount = BigDecimal((item["Value"] as Number).toString())
                    "MpesaReceiptNumber" -> reference = item["Value"].toString()
                    "PhoneNumber" -> phone = item["Value"].toString()
                    "AccountReference" -> account = item["Value"].toString()
                }
            }

            val safeAmount = amount ?: return
            val safeReference = reference ?: return
            val safeAccountRaw = account ?: return

            // 🔥 NORMALIZE ACCOUNT (CRITICAL FIX)
            val safeAccount = safeAccountRaw
                .uppercase()
                .replace("\\s".toRegex(), "")
                .replace("-", "")

            log.info("💰 PAYMENT → ref=$safeReference account=$safeAccount")

            // 🛑 DUPLICATE CHECK
            val exists = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM mpesa_transactions WHERE transaction_code = ?",
                Int::class.java,
                safeReference
            ) ?: 0

            if (exists > 0) {
                log.warn("⚠️ Duplicate transaction ignored")
                return
            }

            // 💾 SAVE RAW PAYMENT
            jdbcTemplate.update(
                """
                INSERT INTO mpesa_transactions(transaction_code, phone_number, account_reference, amount)
                VALUES (?, ?, ?, ?)
                """,
                safeReference,
                phone,
                safeAccount,
                safeAmount
            )

            // 🔍 FIND UNIT USING NORMALIZED VALUE
            val unit = unitRepository.findByReferenceNumberIgnoreCase(safeAccount)
                ?: return log.warn("❌ Unit not found for $safeAccount")

            val tenancy = tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)
                ?: return log.warn("❌ No active tenancy")

            // 💰 PROCESS PAYMENT
            jdbcTemplate.execute(
                "SELECT process_payment(?::uuid, ?::numeric, ?)"
            ) { ps ->
                ps.setObject(1, tenancy.id)
                ps.setBigDecimal(2, safeAmount)
                ps.setString(3, safeReference)
                ps.execute()
            }

            log.info("✅ RENT processed successfully")

        } catch (e: Exception) {
            log.error("❌ Rent callback failed", e)
        }
    }

    // =========================================================
    // 🟢 SUBSCRIPTION CALLBACK
    // =========================================================
    fun processSubscriptionCallback(payload: Map<String, Any>) {

        try {

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *> ?: return

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1
            val checkoutId = callback["CheckoutRequestID"]?.toString()

            // ❌ FAILED PAYMENT
            if (resultCode != 0) {

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
                ?.get("Item") as? List<Map<String, Any>> ?: return

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

            val stkRequest = stkRequestRepository.findByCheckoutRequestId(safeCheckoutId)
                ?: throw RuntimeException("STK request not found")

            val landlord = userRepository.findById(stkRequest.landlordId).orElseThrow()

            // 🛑 DUPLICATE CHECK
            if (platformTransactionRepository.existsByReference(safeReference)) return

            val plan = subscriptionPlanRepository.findMatchingPlan(safeAmount)
                ?: throw RuntimeException("Plan not found")

            // 💰 SAVE TRANSACTION
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

            // 🔥 EXPIRE ONLY ACTIVE
            jdbcTemplate.update(
                "UPDATE subscriptions SET status = 'EXPIRED' WHERE landlord_id = ? AND status = 'ACTIVE'",
                landlord.id
            )

            val start = LocalDateTime.now()
            val end = start.plusMonths(1)

            // 🔥 SAFE INSERT
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
                """,
                UUID.randomUUID(),
                landlord.id,
                plan.id,
                start,
                end
            )

            // ✅ UPDATE STK STATUS
            stkRequest.status = "SUCCESS"
            stkRequestRepository.save(stkRequest)

            log.info("🎉 SUBSCRIPTION ACTIVATED")

        } catch (e: Exception) {
            log.error("❌ Subscription callback crashed", e)
        }
    }
}