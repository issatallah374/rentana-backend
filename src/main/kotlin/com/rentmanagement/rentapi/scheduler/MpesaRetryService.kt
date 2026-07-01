package com.rentmanagement.rentapi.scheduler

import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.math.BigDecimal
import java.util.UUID

@Service
class MpesaRetryService(
    private val jdbcTemplate: JdbcTemplate
) {

    private val log =
        LoggerFactory.getLogger(MpesaRetryService::class.java)

    @Scheduled(fixedDelay = 30000)
    fun retryFailedPayments() {

        val txs =
            jdbcTemplate.queryForList(
                """
                SELECT transaction_code
                FROM mpesa_transactions
                WHERE processed = false
                  AND (retry_count IS NULL OR retry_count < 5)
                ORDER BY created_at ASC
                LIMIT 50
                """.trimIndent()
            )

        txs.forEach { tx ->

            val reference =
                tx["transaction_code"]?.toString()
                    ?: return@forEach

            try {

                retryOnePayment(reference)

            } catch (e: Exception) {

                log.error(
                    "❌ M-PESA RETRY FAILED → ref=$reference",
                    e
                )

                jdbcTemplate.update(
                    """
                    UPDATE mpesa_transactions
                    SET retry_count = COALESCE(retry_count, 0) + 1,
                        last_attempt_at = NOW(),
                        error_message = ?
                    WHERE transaction_code = ?
                    """.trimIndent(),
                    e.message ?: e.javaClass.simpleName,
                    reference
                )
            }
        }
    }

    @Transactional
    fun retryOnePayment(
        reference: String
    ) {

        log.warn(
            "🔁 RETRY START → ref=$reference"
        )

        // =====================================================
        // 🔒 LOCK REAL ROW
        // =====================================================
        // This locks the actual mpesa_transactions row safely.
        // =====================================================

        val txRows = jdbcTemplate.query(
            """
            SELECT
                id,
                amount,
                account_reference
            FROM mpesa_transactions
            WHERE transaction_code = ?
              AND processed = false
            FOR UPDATE
            """.trimIndent(),
            { rs, _ ->
                RetryPaymentRow(
                    amount = rs.getBigDecimal("amount"),
                    accountReference = rs.getString("account_reference")
                )
            },
            reference
        )

        if (txRows.isEmpty()) {

            log.warn(
                "⚠️ RETRY SKIPPED → already processed or missing ref=$reference"
            )

            return
        }

        val tx = txRows.first()
        val account = tx.accountReference
            .uppercase()
            .replace("\\s".toRegex(), "")
            .replace("-", "")

        // =====================================================
        // 🔎 FIND UNIT BY NORMALIZED REFERENCE
        // =====================================================

        val unitIds = jdbcTemplate.query(
            """
            SELECT id
            FROM units
            WHERE UPPER(REPLACE(REPLACE(reference_number, '-', ''), ' ', '')) =
                  UPPER(REPLACE(REPLACE(?, '-', ''), ' ', ''))
            LIMIT 1
            """.trimIndent(),
            { rs, _ ->
                rs.getObject("id", UUID::class.java)
            },
            account
        )

        val unitId = unitIds.firstOrNull()
            ?: throw RuntimeException("Unit not found for account $account")

        // =====================================================
        // 🔎 FIND BEST TENANCY FOR THIS RETRY
        // =====================================================
        // Same rule as live callbacks: old outstanding arrears are paid first;
        // otherwise the current active tenancy receives the payment.

        val tenancyId = resolvePaymentTenancyId(unitId, account)

        // =====================================================
        // 🔁 RE-RUN PAYMENT FUNCTION SAFELY
        // =====================================================

        jdbcTemplate.queryForObject(
            "SELECT process_payment(?, ?, ?)",
            Void::class.java,
            tenancyId,
            tx.amount,
            reference
        )

        // =====================================================
        // ✅ MARK PROCESSED
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
            "✅ M-PESA RETRY PROCESSED → ref=$reference tenancy=$tenancyId"
        )
    }

    private fun resolvePaymentTenancyId(
        unitId: UUID,
        account: String
    ): UUID {

        val tenancyIds = jdbcTemplate.query(
            """
            SELECT id
            FROM (
                SELECT
                    t.id,
                    t.is_active,
                    t.start_date,
                    t.created_at,
                    COALESCE(SUM(
                        CASE
                            WHEN le.entry_type = 'DEBIT' THEN le.amount
                            WHEN le.entry_type = 'CREDIT' THEN -le.amount
                            ELSE 0
                        END
                    ), 0) AS balance
                FROM tenancies t
                LEFT JOIN ledger_entries le
                    ON le.tenancy_id = t.id
                WHERE t.unit_id = ?
                GROUP BY
                    t.id,
                    t.is_active,
                    t.start_date,
                    t.created_at
            ) scored
            ORDER BY
                CASE WHEN balance > 0 THEN 0 ELSE 1 END,
                CASE WHEN balance > 0 THEN start_date END ASC NULLS LAST,
                CASE WHEN is_active THEN 0 ELSE 1 END,
                start_date DESC,
                created_at DESC
            LIMIT 1
            """.trimIndent(),
            { rs, _ ->
                rs.getObject("id", UUID::class.java)
            },
            unitId
        )

        return tenancyIds.firstOrNull()
            ?: throw RuntimeException("No tenancy history found for account $account")
    }

    private data class RetryPaymentRow(
        val amount: BigDecimal,
        val accountReference: String
    )
}
