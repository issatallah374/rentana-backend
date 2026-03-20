package com.rentmanagement.rentapi.services

import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.util.*

@Service
class PayoutService(
    private val jdbcTemplate: JdbcTemplate
) {

    private val log = LoggerFactory.getLogger(PayoutService::class.java)

    // =====================================================
    // 💸 REQUEST PAYOUT (SECURE)
    // =====================================================
    fun requestPayout(
        landlordId: UUID,
        propertyId: UUID,
        amount: BigDecimal,
        method: String,
        destination: String
    ) {

        log.info("💸 Payout request → landlord=$landlordId property=$propertyId amount=$amount")

        // ================================
        // 🔐 VALIDATIONS
        // ================================
        if (amount <= BigDecimal.ZERO) {
            throw RuntimeException("Invalid amount")
        }

        val safeMethod = method.uppercase()
        if (safeMethod !in listOf("MPESA", "BANK")) {
            throw RuntimeException("Invalid payout method")
        }

        if (destination.isBlank()) {
            throw RuntimeException("Destination required")
        }

        // ================================
        // 🔐 VERIFY PROPERTY OWNERSHIP
        // ================================
        val ownsProperty = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM properties WHERE id = ? AND landlord_id = ?",
            Int::class.java,
            propertyId,
            landlordId
        ) ?: 0

        if (ownsProperty == 0) {
            throw RuntimeException("Unauthorized property access")
        }

        // ================================
        // 💰 CHECK BALANCE
        // ================================
        val balance = jdbcTemplate.queryForObject(
            "SELECT balance FROM wallets WHERE property_id = ?",
            BigDecimal::class.java,
            propertyId
        ) ?: BigDecimal.ZERO

        if (balance < amount) {
            throw RuntimeException("Insufficient balance")
        }

        // ================================
        // 🛑 ONE ACTIVE REQUEST ONLY
        // ================================
        val pending = jdbcTemplate.queryForObject(
            """
            SELECT COUNT(*) FROM payout_requests 
            WHERE property_id = ? AND status = 'PENDING'
            """,
            Int::class.java,
            propertyId
        ) ?: 0

        if (pending > 0) {
            throw RuntimeException("You already have a pending payout")
        }

        // ================================
        // 🔒 DESTINATION LOCK
        // ================================
        val existingDestination = jdbcTemplate.query(
            """
            SELECT destination FROM payout_requests 
            WHERE property_id = ? 
            LIMIT 1
            """.trimIndent(),
            arrayOf(propertyId)
        ) { rs, _ -> rs.getString("destination") }
            .firstOrNull()

        if (existingDestination != null && existingDestination != destination) {
            throw RuntimeException("Payout destination locked. Contact support to change.")
        }

        // ================================
        // 💾 INSERT REQUEST
        // ================================
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
            """,
            landlordId,
            propertyId,
            amount,
            safeMethod,
            destination
        )

        log.info("✅ Payout request created successfully")
    }

    // =====================================================
    // 🔥 MARK AS PAID (ADMIN ONLY)
    // =====================================================
    fun markAsPaid(payoutId: UUID) {

        log.info("💰 Processing payout → id=$payoutId")

        val payout = jdbcTemplate.queryForMap(
            "SELECT * FROM payout_requests WHERE id = ?",
            payoutId
        )

        val status = payout["status"]?.toString()

        if (status != "PENDING") {
            throw RuntimeException("Payout already processed")
        }

        // ✅ FIXED (CRITICAL)
        val propertyId = UUID.fromString(payout["property_id"].toString())
        val amount = BigDecimal(payout["amount"].toString())

        // ================================
        // 💰 DOUBLE BALANCE CHECK
        // ================================
        val balance = jdbcTemplate.queryForObject(
            "SELECT balance FROM wallets WHERE property_id = ?",
            BigDecimal::class.java,
            propertyId
        ) ?: BigDecimal.ZERO

        if (balance < amount) {
            throw RuntimeException("Insufficient wallet balance at payout time")
        }

        // ================================
        // 💰 DEDUCT WALLET
        // ================================
        jdbcTemplate.update(
            "UPDATE wallets SET balance = balance - ? WHERE property_id = ?",
            amount,
            propertyId
        )

        // ================================
        // 📒 LEDGER ENTRY
        // ================================
        jdbcTemplate.update(
            """
            INSERT INTO ledger_entries(
                property_id,
                entry_type,
                category,
                amount,
                reference
            )
            VALUES (?, 'DEBIT', 'PAYOUT', ?, ?)
            """,
            propertyId,
            amount,
            payoutId.toString()
        )

        // ================================
        // ✅ MARK PAID
        // ================================
        jdbcTemplate.update(
            """
            UPDATE payout_requests
            SET status = 'PAID',
                processed_at = now()
            WHERE id = ?
            """,
            payoutId
        )

        log.info("🎉 Payout completed successfully")
    }

    // =====================================================
    // ❌ REJECT PAYOUT
    // =====================================================
    fun rejectPayout(payoutId: UUID) {

        val updated = jdbcTemplate.update(
            """
            UPDATE payout_requests
            SET status = 'REJECTED',
                processed_at = now()
            WHERE id = ? AND status = 'PENDING'
            """,
            payoutId
        )

        if (updated == 0) {
            throw RuntimeException("Payout not found or already processed")
        }

        log.warn("❌ Payout rejected → id=$payoutId")
    }
}