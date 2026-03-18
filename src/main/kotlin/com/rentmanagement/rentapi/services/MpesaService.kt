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

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *> ?: return

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1
            if (resultCode != 0) {
                log.warn("❌ Payment failed or cancelled")
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

            log.info("💰 RENT PAYMENT → ref=$safeReference amount=$safeAmount account=$safeAccount")

            val jsonPayload = objectMapper.writeValueAsString(payload)

            // Prevent duplicate
            val exists = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM mpesa_transactions WHERE transaction_code = ?",
                Int::class.java,
                safeReference
            ) ?: 0

            if (exists > 0) {
                log.warn("⚠️ Duplicate transaction ignored: $safeReference")
                return
            }

            // Save transaction
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
                ?: return log.warn("❌ Unit not found: $safeAccount")

            val tenancy = tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)
                ?: return log.warn("❌ No active tenancy")

            // 🔥 Process payment in DB
            jdbcTemplate.execute(
                "SELECT process_payment(?::uuid, ?::numeric, ?)",
                { ps ->
                    ps.setObject(1, tenancy.id)
                    ps.setBigDecimal(2, safeAmount)
                    ps.setString(3, safeReference)
                    ps.execute()
                }
            )

            log.info("✅ RENT processed successfully")

        } catch (e: Exception) {
            log.error("❌ Rent callback failed", e)
        }
    }

    // =========================================================
    // 🟢 SUBSCRIPTIONS (YOUR MONEY 💰)
    // =========================================================
    fun processSubscriptionCallback(payload: Map<String, Any>) {

        try {

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *> ?: return

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1
            if (resultCode != 0) {
                log.warn("❌ Subscription payment failed")
                return
            }

            val items = callback["CallbackMetadata"]
                ?.let { it as? Map<*, *> }
                ?.get("Item") as? List<Map<String, Any>> ?: return

            var amount: BigDecimal? = null
            var reference: String? = null
            var phone: String? = null

            for (item in items) {
                when (item["Name"]) {
                    "Amount" -> amount = BigDecimal((item["Value"] as Number).toString())
                    "MpesaReceiptNumber" -> reference = item["Value"].toString()
                    "PhoneNumber" -> phone = item["Value"].toString()
                }
            }

            val safeAmount = amount ?: return
            val safeReference = reference ?: return
            val safePhone = phone ?: return

            val normalizedPhone = normalizePhone(safePhone)

            log.info("💸 SUBSCRIPTION → phone=$normalizedPhone amount=$safeAmount")

            // Prevent duplicate
            if (platformTransactionRepository.existsByReference(safeReference)) {
                log.warn("⚠️ Duplicate subscription ignored: $safeReference")
                return
            }

            val landlord = userRepository.findByPhone(normalizedPhone)
                ?: throw RuntimeException("Landlord not found")

            val plan = subscriptionPlanRepository.findMatchingPlan(safeAmount)
                ?: throw RuntimeException("Plan not found for amount: $safeAmount")

            // Save revenue
            platformTransactionRepository.save(
                PlatformTransaction(
                    id = UUID.randomUUID(),
                    landlordId = landlord.id!!,
                    amount = safeAmount,
                    reference = safeReference
                )
            )

            // Update wallet
            jdbcTemplate.update(
                "UPDATE platform_wallet SET balance = balance + ?",
                safeAmount
            )

            // Expire old subscriptions
            jdbcTemplate.update(
                "UPDATE subscriptions SET status = 'EXPIRED' WHERE landlord_id = ?",
                landlord.id
            )

            // Create new subscription
            val start = LocalDateTime.now()
            val end = start.plusMonths(1)

            subscriptionRepository.save(
                Subscription(
                    id = UUID.randomUUID(),
                    landlordId = landlord.id!!,
                    planId = plan.id!!,
                    startDate = start,
                    endDate = end,
                    status = "ACTIVE"
                )
            )

            log.info("✅ Subscription activated successfully")

        } catch (e: Exception) {
            log.error("❌ Subscription callback failed", e)
        }
    }

    private fun normalizePhone(phone: String): String {
        return when {
            phone.startsWith("254") -> "0" + phone.substring(3)
            phone.startsWith("+254") -> "0" + phone.substring(4)
            else -> phone
        }
    }
}