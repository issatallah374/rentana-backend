package com.rentmanagement.rentapi.services

import com.fasterxml.jackson.databind.ObjectMapper
import com.rentmanagement.rentapi.models.PlatformTransaction
import com.rentmanagement.rentapi.repository.*
import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.math.BigDecimal
import java.time.LocalDateTime
import java.util.UUID

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

    private val log =
        LoggerFactory.getLogger(MpesaService::class.java)

    private val objectMapper =
        ObjectMapper()

    // =========================================================
    // 🔥 STK INIT (SERVER-CONTROLLED PRICING)
    // =========================================================

    fun initiateStkPush(
        phone: String,
        landlordId: String,
        planId: String
    ) {

        val landlordUUID =
            UUID.fromString(landlordId)

        val planUUID =
            UUID.fromString(planId)

        // ✅ VALIDATE PLAN EXISTS
        val plan =
            subscriptionPlanRepository.findById(planUUID)
                .orElseThrow {
                    RuntimeException("Invalid plan selected")
                }

        // ✅ USE SERVER PRICE (NO FRONTEND TRUST)
        mpesaStkService.stkPush(
            phone = phone,
            amount = plan.price,
            landlordId = landlordUUID,
            planId = planUUID
        )

        log.info(
            "🔥 STK TRIGGERED → landlord=$landlordUUID plan=$planUUID"
        )
    }

    // =========================================================
    // 🟢 C2B PAYMENTS (RENT)
    // =========================================================

    fun processC2BPayment(
        payload: Map<String, Any>
    ) {

        try {

            val reference =
                payload["TransID"]?.toString()
                    ?: return log.error("❌ Missing TransID")

            val amount =
                payload["TransAmount"]
                    ?.toString()
                    ?.toBigDecimalOrNull()
                    ?: return log.error("❌ Missing amount")

            val phone =
                payload["MSISDN"]?.toString()

            val safeAccount =
                payload["BillRefNumber"]
                    ?.toString()
                    ?.uppercase()
                    ?.replace("\\s".toRegex(), "")
                    ?.replace("-", "")
                    ?: return log.error("❌ Missing account")

            log.warn(
                "🔥 C2B RECEIVED → ref=$reference amount=$amount account=$safeAccount phone=$phone"
            )

            handlePayment(
                reference = reference,
                amount = amount,
                phone = phone,
                account = safeAccount,
                payload = payload
            )

        } catch (e: Exception) {

            log.error(
                "❌ C2B FAILED",
                e
            )
        }
    }

    // =========================================================
    // 💰 RENT ENGINE
    // =========================================================

    @Transactional
    private fun handlePayment(
        reference: String,
        amount: BigDecimal,
        phone: String?,
        account: String,
        payload: Map<String, Any>
    ) {

        log.warn(
            "🚀 START PAYMENT → ref=$reference account=$account amount=$amount"
        )

        // =====================================================
        // 1. LOCK EXISTING M-PESA TRANSACTION IF PRESENT
        // =====================================================
        // This prevents double-processing when Safaricom retries
        // the same callback or your retry service re-runs it.
        // =====================================================

        val existing =
            jdbcTemplate.query(
                """
                SELECT processed
                FROM mpesa_transactions
                WHERE transaction_code = ?
                FOR UPDATE
                """.trimIndent(),
                { rs, _ ->
                    rs.getBoolean("processed")
                },
                reference
            )

        if (existing.isNotEmpty()) {

            val alreadyProcessed =
                existing.first()

            if (alreadyProcessed) {

                log.warn(
                    "⚠️ DUPLICATE ALREADY PROCESSED → $reference"
                )

                return
            }

            log.warn(
                "🔁 EXISTING UNPROCESSED TRANSACTION → $reference"
            )

        } else {

            // =====================================================
            // 2. SAVE RAW TRANSACTION ONLY IF IT DOES NOT EXIST
            // =====================================================

            jdbcTemplate.update(
                """
                INSERT INTO mpesa_transactions(
                    transaction_code,
                    phone_number,
                    account_reference,
                    amount,
                    raw_payload,
                    processed,
                    created_at,
                    retry_count
                )
                VALUES (?, ?, ?, ?, ?::jsonb, false, NOW(), 0)
                """.trimIndent(),
                reference,
                phone,
                account,
                amount,
                objectMapper.writeValueAsString(payload)
            )

            log.info(
                "📦 TRANSACTION SAVED → $reference"
            )
        }

        // =====================================================
        // 3. FIND UNIT
        // =====================================================

        val unit =
            unitRepository.findByReferenceNumberIgnoreCase(account)
                ?: throw RuntimeException(
                    "Unit not found for account $account"
                )

        // =====================================================
        // 4. FIND ACTIVE TENANCY
        // =====================================================

        val tenancy =
            tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)
                ?: throw RuntimeException(
                    "No active tenancy for account $account"
                )

        // =====================================================
        // 5. PROCESS PAYMENT IN DATABASE
        // =====================================================
        // IMPORTANT:
        // process_payment is a PostgreSQL FUNCTION called by SELECT.
        // Do NOT use jdbcTemplate.update("SELECT process_payment...")
        // because SELECT returns a result row.
        // =====================================================

        jdbcTemplate.queryForObject(
            "SELECT process_payment(?, ?, ?)",
            Void::class.java,
            tenancy.id,
            amount,
            reference
        )

        log.info(
            "💰 DB FUNCTION EXECUTED → $reference"
        )

        // =====================================================
        // 6. MARK M-PESA TRANSACTION AS PROCESSED
        // =====================================================

        jdbcTemplate.update(
            """
            UPDATE mpesa_transactions
            SET processed = true,
                last_attempt_at = NOW(),
                error_message = NULL
            WHERE transaction_code = ?
            """.trimIndent(),
            reference
        )

        log.info(
            "✅ PAYMENT MARKED PROCESSED → $reference"
        )
    }

    // =========================================================
    // 🟣 SUBSCRIPTION CALLBACK (PLAN-BASED, NO AMOUNT MATCH)
    // =========================================================

    fun processSubscriptionCallback(
        payload: Map<String, Any>
    ) {

        try {

            log.info(
                "🔥 STK CALLBACK RECEIVED"
            )

            val callback =
                payload["Body"]
                    ?.let { it as? Map<*, *> }
                    ?.get("stkCallback") as? Map<*, *>
                    ?: return log.error("❌ Missing stkCallback")

            val resultCode =
                (callback["ResultCode"] as? Number)?.toInt() ?: -1

            val checkoutId =
                callback["CheckoutRequestID"]?.toString()
                    ?: return log.error("❌ Missing checkoutId")

            val stkRequest =
                stkRequestRepository.findByCheckoutRequestId(checkoutId)
                    ?: return log.error("❌ STK request not found")

            // ✅ PREVENT DOUBLE PROCESSING
            if (stkRequest.status == "SUCCESS") {

                log.warn(
                    "⚠️ Already processed → $checkoutId"
                )

                return
            }

            // ❌ FAILED PAYMENT
            if (resultCode != 0) {

                stkRequest.status =
                    "FAILED"

                stkRequestRepository.save(stkRequest)

                log.warn(
                    "❌ SUBSCRIPTION FAILED → $checkoutId"
                )

                return
            }

            val items =
                callback["CallbackMetadata"]
                    ?.let { it as? Map<*, *> }
                    ?.get("Item") as? List<Map<String, Any>>
                    ?: return log.error("❌ Missing metadata")

            var reference: String? =
                null

            items.forEach { item ->

                if (item["Name"] == "MpesaReceiptNumber") {

                    reference =
                        item["Value"].toString()
                }
            }

            val safeReference =
                reference
                    ?: return log.error("❌ Missing reference")

            // =====================================================
            // ✅ PLAN FROM STK (SOURCE OF TRUTH)
            // =====================================================

            val planId =
                stkRequest.planId

            val plan =
                subscriptionPlanRepository.findById(planId).orElse(null)
                    ?: return log.error("❌ Plan not found")

            val landlord =
                userRepository.findById(stkRequest.landlordId).orElseThrow()

            // ✅ PREVENT DUPLICATE SUBSCRIPTION TRANSACTION
            if (platformTransactionRepository.existsByReference(safeReference)) {

                log.warn(
                    "⚠️ Duplicate subscription → $safeReference"
                )

                return
            }

            // 💾 SAVE PLATFORM TRANSACTION
            platformTransactionRepository.save(
                PlatformTransaction(
                    id = UUID.randomUUID(),
                    landlordId = landlord.id!!,
                    amount = plan.price,
                    reference = safeReference
                )
            )

            // 💰 UPDATE PLATFORM WALLET
            jdbcTemplate.update(
                """
                UPDATE platform_wallet
                SET balance = balance + ?
                """.trimIndent(),
                plan.price
            )

            // 🔄 EXPIRE OLD SUBSCRIPTIONS
            jdbcTemplate.update(
                """
                UPDATE subscriptions
                SET status = 'EXPIRED'
                WHERE landlord_id = ?
                  AND status = 'ACTIVE'
                """.trimIndent(),
                landlord.id
            )

            // ✅ CREATE NEW SUBSCRIPTION
            val start =
                LocalDateTime.now()

            val end =
                start.plusMonths(1)

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

            // ✅ MARK STK REQUEST SUCCESS
            stkRequest.status =
                "SUCCESS"

            stkRequestRepository.save(stkRequest)

            log.info(
                "🎉 SUBSCRIPTION ACTIVATED → landlord=${landlord.id}"
            )

        } catch (e: Exception) {

            log.error(
                "❌ SUBSCRIPTION CALLBACK FAILED",
                e
            )
        }
    }
}