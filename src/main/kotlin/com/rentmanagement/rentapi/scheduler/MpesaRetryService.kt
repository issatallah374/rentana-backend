package com.rentmanagement.rentapi.scheduler

import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

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
        // DO NOT use COUNT(*) FOR UPDATE.
        // PostgreSQL does not allow FOR UPDATE with aggregates.
        // This locks the actual mpesa_transactions row safely.
        // =====================================================

        val lockedRows =
            jdbcTemplate.query(
                """
                SELECT id
                FROM mpesa_transactions
                WHERE transaction_code = ?
                  AND processed = false
                FOR UPDATE
                """.trimIndent(),
                { rs, _ ->
                    rs.getObject("id")
                },
                reference
            )

        if (lockedRows.isEmpty()) {

            log.warn(
                "⚠️ RETRY SKIPPED → already processed or missing ref=$reference"
            )

            return
        }

        // =====================================================
        // 🔁 RE-RUN DB FUNCTION
        // =====================================================
        // PostgreSQL function is called with SELECT, so use
        // queryForObject instead of jdbcTemplate.update.
        // =====================================================

        jdbcTemplate.queryForObject(
            "SELECT process_payment_by_reference(?)",
            Void::class.java,
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
            "✅ M-PESA RETRY PROCESSED → ref=$reference"
        )
    }
}