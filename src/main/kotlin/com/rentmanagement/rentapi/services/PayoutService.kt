package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.exceptions.BadRequestException
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

        // ✅ VALIDATION
        if (amount <= BigDecimal.ZERO) {
            throw BadRequestException("Enter a valid amount")
        }

        // 🔥 MINIMUM = 3 KES
        if (amount < BigDecimal("3")) {
            throw BadRequestException("Minimum withdrawal is KES 3")
        }

        // ✅ OWNERSHIP CHECK
        val ownsProperty = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM properties WHERE id = ? AND landlord_id = ?",
            Int::class.java,
            propertyId,
            landlordId
        ) ?: 0

        if (ownsProperty == 0) {
            throw BadRequestException("You are not authorized for this property")
        }

        // ✅ BALANCE CHECK
        val balance = jdbcTemplate.queryForObject(
            "SELECT balance FROM wallets WHERE property_id = ?",
            BigDecimal::class.java,
            propertyId
        ) ?: BigDecimal.ZERO

        if (amount > balance) {
            throw BadRequestException("Insufficient balance")
        }

        // 🔥 KEEP SMALL BALANCE (optional safety)
        val minimumRemaining = BigDecimal("1")

        if (balance - amount < minimumRemaining) {
            throw BadRequestException("Leave at least KES 1 in wallet")
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
            else -> throw BadRequestException("Please complete payout setup first")
        }

        // ✅ PREVENT MULTIPLE REQUESTS
        val pending = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM payout_requests WHERE property_id = ? AND status = 'PENDING'",
            Int::class.java,
            propertyId
        ) ?: 0

        if (pending > 0) {
            throw BadRequestException("You already have a pending payout")
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
            throw BadRequestException("Payout already processed")
        }

        val propertyId = UUID.fromString(payout["property_id"].toString())
        val amount = BigDecimal(payout["amount"].toString())

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
            throw BadRequestException("Balance update failed")
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
            throw BadRequestException("Payout not found or already processed")
        }

        log.info("✅ payout rejected → id=$payoutId")
    }
}