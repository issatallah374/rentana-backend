package com.rentmanagement.rentapi.services

import com.fasterxml.jackson.databind.ObjectMapper
import com.rentmanagement.rentapi.repository.*
import com.rentmanagement.rentapi.models.*
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.slf4j.LoggerFactory
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
    private val jdbcTemplate: JdbcTemplate
) {

    private val log = LoggerFactory.getLogger(MpesaService::class.java)
    private val objectMapper = ObjectMapper()

    // =========================================================
    // 🔵 TENANT RENT PAYMENTS
    // =========================================================
    fun processPaymentCallback(payload: Map<String, Any>) {

        try {
            log.info("🔥 RENT CALLBACK: $payload")

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *> ?: return

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1
            val resultDesc = callback["ResultDesc"]?.toString()

            if (resultCode != 0) {
                log.warn("❌ Payment failed → code=$resultCode desc=$resultDesc")
                return
            }

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
            val safeAccount = account ?: return

            log.info("💰 RENT PAYMENT → ref=$safeReference amount=$safeAmount")

            val jsonPayload = objectMapper.writeValueAsString(payload)

            val exists = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM mpesa_transactions WHERE transaction_code = ?",
                Int::class.java,
                safeReference
            ) ?: 0

            if (exists > 0) {
                log.warn("⚠️ Duplicate transaction ignored")
                return
            }

            jdbcTemplate.update(
                """
                INSERT INTO mpesa_transactions(
                    transaction_code,
                    phone_number,
                    account_reference,
                    amount,
                    raw_payload
                )
                VALUES (?, ?, ?, ?, ?::jsonb)
                """,
                safeReference,
                phone,
                safeAccount,
                safeAmount,
                jsonPayload
            )

            val unit = unitRepository.findByReferenceNumber(safeAccount)
                ?: return log.warn("❌ Unit not found")

            val tenancy = tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)
                ?: return log.warn("❌ No active tenancy")

            jdbcTemplate.execute(
                "SELECT process_payment(?::uuid, ?::numeric, ?)",
                { ps ->
                    ps.setObject(1, tenancy.id)
                    ps.setBigDecimal(2, safeAmount)
                    ps.setString(3, safeReference)
                    ps.execute()
                }
            )

            log.info("✅ RENT processed")

        } catch (e: Exception) {
            log.error("❌ Rent callback failed", e)
        }
    }

    // =========================================================
    // 🟢 SUBSCRIPTIONS (FINAL DEBUGGED VERSION)
    // =========================================================
    fun processSubscriptionCallback(payload: Map<String, Any>) {

        try {

            // 🔥 FULL CALLBACK LOG
            log.info("🔥 SUBSCRIPTION CALLBACK FULL: $payload")

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *> ?: return

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1
            val resultDesc = callback["ResultDesc"]?.toString()

            // ❌ FAILED PAYMENT
            if (resultCode != 0) {
                log.warn("❌ Subscription failed → code=$resultCode desc=$resultDesc")
                return
            }

            val items = callback["CallbackMetadata"]
                ?.let { it as? Map<*, *> }
                ?.get("Item") as? List<Map<String, Any>> ?: return

            var amount: BigDecimal? = null
            var reference: String? = null
            var account: String? = null

            for (item in items) {
                when (item["Name"]) {
                    "Amount" -> amount = BigDecimal((item["Value"] as Number).toString())
                    "MpesaReceiptNumber" -> reference = item["Value"].toString()
                    "AccountReference" -> account = item["Value"].toString()
                }
            }

            val safeAmount = amount ?: return
            val safeReference = reference ?: return
            val safeAccount = account ?: return

            log.info("💸 SUBSCRIPTION SUCCESS → amount=$safeAmount account=$safeAccount")

            // 🔥 Extract landlordId
            val landlordId = safeAccount.removePrefix("SUB_")

            val landlord = userRepository.findById(UUID.fromString(landlordId))
                .orElseThrow {
                    RuntimeException("❌ Landlord not found for id=$landlordId")
                }

            // 🛑 Duplicate check
            if (platformTransactionRepository.existsByReference(safeReference)) {
                log.warn("⚠️ Duplicate subscription ignored")
                return
            }

            val plan = subscriptionPlanRepository.findMatchingPlan(safeAmount)
                ?: throw RuntimeException("❌ Plan not found for amount=$safeAmount")

            // 💰 Save transaction
            platformTransactionRepository.save(
                PlatformTransaction(
                    id = UUID.randomUUID(),
                    landlordId = landlord.id!!,
                    amount = safeAmount,
                    reference = safeReference
                )
            )

            // 💰 Update wallet
            jdbcTemplate.update(
                "UPDATE platform_wallet SET balance = balance + ?",
                safeAmount
            )

            // 🔄 Expire old subscriptions
            jdbcTemplate.update(
                "UPDATE subscriptions SET status = 'EXPIRED' WHERE landlord_id = ?",
                landlord.id
            )

            // ✅ New subscription
            val start = LocalDateTime.now()

            subscriptionRepository.save(
                Subscription(
                    id = UUID.randomUUID(),
                    landlordId = landlord.id!!,
                    planId = plan.id!!,
                    startDate = start,
                    endDate = start.plusMonths(1),
                    status = "ACTIVE"
                )
            )

            log.info("🎉 SUBSCRIPTION ACTIVATED SUCCESSFULLY")

        } catch (e: Exception) {
            log.error("❌ Subscription callback crashed", e)
        }
    }
}