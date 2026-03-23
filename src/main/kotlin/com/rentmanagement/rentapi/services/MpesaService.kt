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
    private val subscriptionPlanRepository: SubscriptionPlanRepository,
    private val platformTransactionRepository: PlatformTransactionRepository,
    private val stkRequestRepository: StkRequestRepository,
    private val jdbcTemplate: JdbcTemplate,
    private val mpesaStkService: MpesaStkService
) {

    private val log = LoggerFactory.getLogger(MpesaService::class.java)
    private val objectMapper = ObjectMapper()

    // =========================================================
    // 🔥 STK INIT (SERVER-CONTROLLED PRICING)
    // =========================================================
    fun initiateStkPush(
        phone: String,
        landlordId: String,
        planId: String
    ) {

        val landlordUUID = UUID.fromString(landlordId)
        val planUUID = UUID.fromString(planId)

        // ✅ VALIDATE PLAN EXISTS
        val plan = subscriptionPlanRepository.findById(planUUID)
            .orElseThrow { RuntimeException("Invalid plan selected") }

        // ✅ USE SERVER PRICE (NO FRONTEND TRUST)
        mpesaStkService.stkPush(
            phone = phone,
            amount = plan.price,
            landlordId = landlordUUID,
            planId = planUUID
        )

        log.info("🔥 STK TRIGGERED → landlord=$landlordUUID plan=$planUUID")
    }

    // =========================================================
// 🟢 C2B PAYMENTS (RENT)
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

            log.warn("🔥 C2B RECEIVED → ref=$reference amount=$amount account=$safeAccount phone=$phone")

            handlePayment(reference, amount, phone, safeAccount, payload)

        } catch (e: Exception) {
            log.error("❌ C2B FAILED", e)
        }
    }


    // =========================================================
// 💰 RENT ENGINE
// =========================================================
    private fun handlePayment(
        reference: String,
        amount: BigDecimal,
        phone: String?,
        account: String,
        payload: Map<String, Any>
    ) {

        try {

            log.warn("🚀 START PAYMENT → ref=$reference account=$account amount=$amount")

            // =====================================================
            // 1. DUPLICATE CHECK
            // =====================================================
            val exists = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM mpesa_transactions WHERE transaction_code = ?",
                Int::class.java,
                reference
            ) ?: 0

            if (exists > 0) {
                log.warn("⚠️ DUPLICATE PAYMENT IGNORED → $reference")
                return
            }

            // =====================================================
            // 2. SAVE RAW TRANSACTION
            // =====================================================
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

            log.info("📦 TRANSACTION SAVED → $reference")

            // =====================================================
            // 3. FIND UNIT
            // =====================================================
            val unit = unitRepository.findByReferenceNumberIgnoreCase(account)

            if (unit == null) {
                log.error("❌ UNIT NOT FOUND → $account")
                return
            }

            log.info("🏢 UNIT FOUND → id=${unit.id}")

            // =====================================================
            // 4. FIND TENANCY
            // =====================================================
            val tenancy = tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)

            if (tenancy == null) {
                log.error("❌ NO ACTIVE TENANCY → unit=${unit.id}")
                return
            }

            log.info("🏠 TENANCY FOUND → id=${tenancy.id}")

            // =====================================================
            // 5. PROCESS PAYMENT (FIXED ✅)
            // =====================================================
            jdbcTemplate.update(
                "SELECT process_payment(?::uuid, ?::numeric, ?)",
                tenancy.id,
                amount,
                reference
            )

            log.info("💰 DB FUNCTION EXECUTED")

            // =====================================================
            // 6. MARK AS PROCESSED
            // =====================================================
            jdbcTemplate.update(
                "UPDATE mpesa_transactions SET processed = true WHERE transaction_code = ?",
                reference
            )

            log.info("✅ PAYMENT MARKED PROCESSED → $reference")

            log.warn("🎉 RENT PAYMENT SUCCESS → ref=$reference amount=$amount")

        } catch (e: Exception) {
            log.error("❌ HANDLE PAYMENT FAILED → $reference", e)
        }
    }

    // =========================================================
    // 🟣 SUBSCRIPTION CALLBACK (PLAN-BASED, NO AMOUNT MATCH)
    // =========================================================
    fun processSubscriptionCallback(payload: Map<String, Any>) {

        try {

            log.info("🔥 STK CALLBACK RECEIVED")

            val callback = payload["Body"]
                ?.let { it as? Map<*, *> }
                ?.get("stkCallback") as? Map<*, *>
                ?: return log.error("❌ Missing stkCallback")

            val resultCode = (callback["ResultCode"] as? Number)?.toInt() ?: -1
            val checkoutId = callback["CheckoutRequestID"]?.toString()
                ?: return log.error("❌ Missing checkoutId")

            val stkRequest = stkRequestRepository.findByCheckoutRequestId(checkoutId)
                ?: return log.error("❌ STK request not found")

            // ✅ PREVENT DOUBLE PROCESSING
            if (stkRequest.status == "SUCCESS") {
                log.warn("⚠️ Already processed → $checkoutId")
                return
            }

            // ❌ FAILED PAYMENT
            if (resultCode != 0) {
                stkRequest.status = "FAILED"
                stkRequestRepository.save(stkRequest)
                log.warn("❌ SUBSCRIPTION FAILED → $checkoutId")
                return
            }

            val items = callback["CallbackMetadata"]
                ?.let { it as? Map<*, *> }
                ?.get("Item") as? List<Map<String, Any>>
                ?: return log.error("❌ Missing metadata")

            var reference: String? = null

            items.forEach {
                if (it["Name"] == "MpesaReceiptNumber") {
                    reference = it["Value"].toString()
                }
            }

            val safeReference = reference ?: return log.error("❌ Missing reference")

            // =====================================================
            // ✅ PLAN FROM STK (SOURCE OF TRUTH)
            // =====================================================
            val planId = stkRequest.planId

            val plan = subscriptionPlanRepository.findById(planId).orElse(null)
                ?: return log.error("❌ Plan not found")

            val landlord = userRepository.findById(stkRequest.landlordId).orElseThrow()

            // DUPLICATE CHECK
            if (platformTransactionRepository.existsByReference(safeReference)) {
                log.warn("⚠️ Duplicate subscription → $safeReference")
                return
            }

            // 💾 SAVE TRANSACTION
            platformTransactionRepository.save(
                PlatformTransaction(
                    id = UUID.randomUUID(),
                    landlordId = landlord.id!!,
                    amount = plan.price,
                    reference = safeReference
                )
            )

            // 💰 UPDATE WALLET
            jdbcTemplate.update(
                "UPDATE platform_wallet SET balance = balance + ?",
                plan.price
            )

            // 🔄 EXPIRE OLD
            jdbcTemplate.update(
                "UPDATE subscriptions SET status='EXPIRED' WHERE landlord_id=? AND status='ACTIVE'",
                landlord.id
            )

            // ✅ CREATE NEW SUBSCRIPTION
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

            // ✅ MARK SUCCESS
            stkRequest.status = "SUCCESS"
            stkRequestRepository.save(stkRequest)

            log.info("🎉 SUBSCRIPTION ACTIVATED → landlord=${landlord.id}")

        } catch (e: Exception) {
            log.error("❌ SUBSCRIPTION CALLBACK FAILED", e)
        }
    }
}