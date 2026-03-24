package com.rentmanagement.rentapi.scheduler

import com.rentmanagement.rentapi.services.DashboardSnapshotService
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.scheduling.annotation.Scheduled
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service


@Service
class MpesaRetryService(
    private val jdbcTemplate: JdbcTemplate
) {

    @Scheduled(fixedDelay = 30000)
    fun retryFailedPayments() {

        val txs = jdbcTemplate.queryForList(
            """
            SELECT transaction_code, amount, account_reference
            FROM mpesa_transactions
            WHERE processed = false
            AND (retry_count IS NULL OR retry_count < 5)
            LIMIT 50
            """
        )

        txs.forEach { tx ->
            val reference = tx["transaction_code"].toString()

            try {

                // 🔒 LOCK ROW (IMPORTANT)
                val locked = jdbcTemplate.queryForObject(
                    """
                    SELECT COUNT(*) FROM mpesa_transactions
                    WHERE transaction_code = ? AND processed = false
                    FOR UPDATE
                    """,
                    Int::class.java,
                    reference
                ) ?: 0

                if (locked == 0) return@forEach

                // 🔁 RE-RUN DB FUNCTION ONLY
                jdbcTemplate.update(
                    "SELECT process_payment_by_reference(?)",
                    reference
                )

                // ✅ mark processed
                jdbcTemplate.update(
                    "UPDATE mpesa_transactions SET processed = true WHERE transaction_code = ?",
                    reference
                )

            } catch (e: Exception) {

                jdbcTemplate.update(
                    """
                    UPDATE mpesa_transactions
                    SET retry_count = COALESCE(retry_count,0) + 1,
                        last_attempt_at = NOW(),
                        error_message = ?
                    WHERE transaction_code = ?
                    """,
                    e.message,
                    reference
                )
            }
        }
    }
}