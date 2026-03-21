package com.rentmanagement.rentapi.services

import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.math.BigDecimal
import java.util.*

@Service
class PayoutService(
    private val jdbcTemplate: JdbcTemplate
) {

    private val log = LoggerFactory.getLogger(PayoutService::class.java)

    // =====================================================
    // 💸 REQUEST PAYOUT
    // =====================================================
    fun requestPayout(
        landlordId: UUID,
        propertyId: UUID,
        amount: BigDecimal
    ) {

        log.info("💸 Request payout → landlord=$landlordId property=$propertyId amount=$amount")

        if (amount <= BigDecimal.ZERO) {
            throw RuntimeException("Invalid amount")
        }

        if (amount < BigDecimal("600")) {
            throw RuntimeException("Minimum withdrawal is 600")
        }

        // ✅ OWNERSHIP CHECK
        val ownsProperty = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM properties WHERE id = ? AND landlord_id = ?",
            Int::class.java,
            propertyId,
            landlordId
        ) ?: 0

        if (ownsProperty == 0) {
            throw RuntimeException("Unauthorized")
        }

        // ✅ BALANCE CHECK
        val balance = jdbcTemplate.queryForObject(
            "SELECT balance FROM wallets WHERE property_id = ?",
            BigDecimal::class.java,
            propertyId
        ) ?: BigDecimal.ZERO

        if (balance < amount) {
            throw RuntimeException("Insufficient balance")
        }

        // ✅ GET PAYOUT METHOD
        val wallet = jdbcTemplate.queryForMap(
            "SELECT mpesa_phone, account_number FROM wallets WHERE property_id = ?",
            propertyId
        )

        val mpesa = wallet["mpesa_phone"]?.toString()
        val bank = wallet["account_number"]?.toString()

        val (method, destination) = when {
            !mpesa.isNullOrBlank() -> "MPESA" to mpesa
            !bank.isNullOrBlank() -> "BANK" to bank
            else -> throw RuntimeException("Payout setup incomplete")
        }

        // ✅ PREVENT MULTIPLE PENDING REQUESTS
        val pending = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM payout_requests WHERE property_id = ? AND status = 'PENDING'",
            Int::class.java,
            propertyId
        ) ?: 0

        if (pending > 0) {
            throw RuntimeException("Pending payout exists")
        }

        // ✅ INSERT REQUEST
        jdbcTemplate.update(
            """
            INSERT INTO payout_requests(
                landlord_id,
                property_id,
                amount,
                method,
                destination,
                status
            )
            VALUES (?, ?, ?, ?, ?, 'PENDING')
            """.trimIndent(),
            landlordId,
            propertyId,
            amount,
            method,
            destination
        )

        log.info("✅ payout requested → $method → $destination")
    }

    // =====================================================
    // 🔥 ADMIN MARK AS PAID
    // =====================================================
    @Transactional
    fun markAsPaid(payoutId: UUID) {

        log.info("🔥 Mark payout as PAID → id=$payoutId")

        val payout = jdbcTemplate.queryForMap(
            "SELECT * FROM payout_requests WHERE id = ? FOR UPDATE",
            payoutId
        )

        if (payout["status"] != "PENDING") {
            throw RuntimeException("Already processed")
        }

        val propertyId = UUID.fromString(payout["property_id"].toString())
        val amount = BigDecimal(payout["amount"].toString())

        // ✅ DEDUCT BALANCE SAFELY
        val updated = jdbcTemplate.update(
            """
            UPDATE wallets
            SET balance = balance - ?
            WHERE property_id = ?
            AND balance >= ?
            """.trimIndent(),
            amount,
            propertyId,
            amount
        )

        if (updated == 0) {
            throw RuntimeException("Balance issue")
        }

        // ✅ LEDGER ENTRY
        jdbcTemplate.update(
            """
            INSERT INTO ledger_entries(
                property_id,
                entry_type,
                category,
                amount,
                reference,
                created_at
            )
            VALUES (?, 'DEBIT', 'PAYOUT', ?, ?, now())
            """.trimIndent(),
            propertyId,
            amount,
            "PAYOUT:$payoutId"
        )

        // ✅ UPDATE STATUS
        jdbcTemplate.update(
            """
            UPDATE payout_requests
            SET status = 'PAID',
                processed_at = now()
            WHERE id = ?
            """.trimIndent(),
            payoutId
        )

        log.info("✅ payout marked as PAID → id=$payoutId")
    }

    // =====================================================
    // ❌ REJECT PAYOUT
    // =====================================================
    fun rejectPayout(payoutId: UUID) {

        log.info("❌ Reject payout → id=$payoutId")

        val updated = jdbcTemplate.update(
            """
            UPDATE payout_requests
            SET status = 'REJECTED',
                processed_at = now()
            WHERE id = ? AND status = 'PENDING'
            """.trimIndent(),
            payoutId
        )

        if (updated == 0) {
            throw RuntimeException("Not found or already processed")
        }

        log.info("✅ payout rejected → id=$payoutId")
    }
}