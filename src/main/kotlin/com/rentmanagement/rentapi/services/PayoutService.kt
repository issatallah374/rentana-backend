package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.exceptions.BadRequestException
import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.math.BigDecimal
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.*

@Service
class PayoutService(
    private val jdbcTemplate: JdbcTemplate
) {

    private val log = LoggerFactory.getLogger(PayoutService::class.java)

    private val kenyaZone = ZoneId.of("Africa/Nairobi")

    // =====================================================
    // 💸 REQUEST PAYOUT
    // =====================================================
    @Transactional
    fun requestPayout(
        landlordId: UUID,
        propertyId: UUID,
        amount: BigDecimal
    ) {

        log.info("💸 Request payout → landlord=$landlordId property=$propertyId amount=$amount")

        // ===============================
        // ✅ VALIDATION
        // ===============================
        if (amount <= BigDecimal.ZERO) {
            throw BadRequestException("Enter a valid amount")
        }

        if (amount < BigDecimal("3")) {
            throw BadRequestException("Minimum withdrawal is KES 3")
        }

        // ===============================
        // 🔐 OWNERSHIP CHECK
        // ===============================
        val ownsProperty = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM properties WHERE id = ? AND landlord_id = ?",
            Int::class.java,
            propertyId,
            landlordId
        ) ?: 0

        if (ownsProperty == 0) {
            throw BadRequestException("You are not authorized for this property")
        }

        // ===============================
        // 💰 CORRECT WALLET BALANCE (🔥 FIXED FULLY)
        // ===============================
        val balance = jdbcTemplate.queryForObject(
            """
            SELECT COALESCE(SUM(
                CASE
                    WHEN entry_type = 'CREDIT' THEN amount
                    WHEN entry_type = 'DEBIT' AND category IN ('PAYOUT', 'WITHDRAWAL') THEN -amount
                    ELSE 0
                END
            ), 0)
            FROM ledger_entries
            WHERE property_id = ?
            """.trimIndent(),
            BigDecimal::class.java,
            propertyId
        ) ?: BigDecimal.ZERO

        log.info("💰 Current balance → $balance")

        // ❌ NO MONEY
        if (balance <= BigDecimal.ZERO) {
            throw BadRequestException("No funds available")
        }

        // ❌ INSUFFICIENT
        if (amount > balance) {
            throw BadRequestException("Insufficient balance")
        }

        // 🔒 SAFETY BUFFER
        val minimumRemaining = BigDecimal("1")
        if (balance.subtract(amount) < minimumRemaining) {
            throw BadRequestException("Leave at least KES 1 in wallet")
        }

        // ===============================
        // ✅ GET PAYOUT METHOD
        // ===============================
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

        // ===============================
        // 🚫 PREVENT MULTIPLE REQUESTS
        // ===============================
        val pending = jdbcTemplate.queryForObject(
            """
            SELECT COUNT(*) 
            FROM payout_requests 
            WHERE property_id = ? AND status = 'PENDING'
            """.trimIndent(),
            Int::class.java,
            propertyId
        ) ?: 0

        if (pending > 0) {
            throw BadRequestException("You already have a pending payout")
        }

        // ===============================
        // 💾 INSERT PAYOUT REQUEST
        // ===============================
        val now = LocalDateTime.now(kenyaZone)

        jdbcTemplate.update(
            """
            INSERT INTO payout_requests (
                id,
                landlord_id,
                property_id,
                amount,
                method,
                destination,
                status,
                created_at
            )
            VALUES (?, ?, ?, ?, ?, ?, 'PENDING', ?)
            """.trimIndent(),
            UUID.randomUUID(),
            landlordId,
            propertyId,
            amount,
            method,
            destination,
            now
        )

        log.info("✅ payout requested → $method → $destination")
    }

    // =====================================================
// =====================================================
// 🔥 ADMIN MARK AS PAID (CORRECT + SECURE)
// =====================================================
    @Transactional
    fun markAsPaid(
        payoutId: UUID,
        adminId: UUID,
        nationalId: String
    ) {

        log.info("🔥 Mark payout as PAID → id=$payoutId admin=$adminId")

        if (nationalId.isBlank()) {
            throw BadRequestException("National ID is required")
        }

        // 🔒 Lock payout row
        val payout = jdbcTemplate.queryForMap(
            "SELECT * FROM payout_requests WHERE id = ? FOR UPDATE",
            payoutId
        )

        if (payout["status"] != "PENDING") {
            throw BadRequestException("Payout already processed")
        }

        val propertyId = UUID.fromString(payout["property_id"].toString())
        val amount = BigDecimal(payout["amount"].toString())

        // =====================================================
        // 🔐 VERIFY ADMIN NATIONAL ID (✅ CORRECT USER)
        // =====================================================
        val adminNationalIdHash = jdbcTemplate.queryForObject(
            "SELECT national_id_hash FROM users WHERE id = ?",
            String::class.java,
            adminId
        ) ?: throw BadRequestException("Admin has no National ID set")

        val encoder = org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder()

        val isValid = encoder.matches(nationalId, adminNationalIdHash)

        if (!isValid) {
            log.warn("❌ INVALID ADMIN NATIONAL ID → payout=$payoutId admin=$adminId")
            throw BadRequestException("Invalid National ID")
        }

        val now = LocalDateTime.now(kenyaZone)

        // =====================================================
        // ✅ WRITE LEDGER (SOURCE OF TRUTH)
        // =====================================================
        jdbcTemplate.update(
            """
        INSERT INTO ledger_entries(
            property_id,
            entry_type,
            category,
            amount,
            entry_month,
            entry_year,
            reference,
            created_at
        )
        VALUES (?, 'DEBIT', 'PAYOUT', ?, ?, ?, ?, ?)
        """.trimIndent(),
            propertyId,
            amount,
            now.monthValue,
            now.year,
            "PAYOUT:$payoutId",
            now
        )

        // =====================================================
        // ✅ UPDATE PAYOUT (SAFE)
        // =====================================================
        jdbcTemplate.update(
            """
        UPDATE payout_requests
        SET status = 'PAID',
            processed_at = ?,
            processed_by = ?,
            national_id = ?
        WHERE id = ?
        """.trimIndent(),
            now,
            adminId,
            "VERIFIED", // 🔥 NEVER store real ID
            payoutId
        )

        log.info("✅ payout marked as PAID → VERIFIED → id=$payoutId")
    }


    // =====================================================
// =====================================================
// ❌ REJECT PAYOUT (IMPROVED)
// =====================================================
    @Transactional
    fun rejectPayout(
        payoutId: UUID,
        adminId: UUID
    ) {

        log.info("❌ Reject payout → id=$payoutId admin=$adminId")

        val payout = jdbcTemplate.queryForMap(
            "SELECT status FROM payout_requests WHERE id = ? FOR UPDATE",
            payoutId
        )

        if (payout["status"] != "PENDING") {
            throw BadRequestException("Payout already processed")
        }

        val now = LocalDateTime.now(kenyaZone)

        jdbcTemplate.update(
            """
        UPDATE payout_requests
        SET status = 'REJECTED',
            processed_at = ?,
            processed_by = ?
        WHERE id = ?
        """.trimIndent(),
            now,
            adminId,
            payoutId
        )

        log.info("✅ payout rejected → id=$payoutId")
    }
}