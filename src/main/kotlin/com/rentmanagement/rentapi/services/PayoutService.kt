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
import com.rentmanagement.rentapi.repository.WalletRepository
import org.springframework.security.crypto.password.PasswordEncoder

@Service
class PayoutService(
    private val jdbcTemplate: JdbcTemplate,
    private val walletRepository: WalletRepository,
    private val passwordEncoder: PasswordEncoder
) {

    private val log = LoggerFactory.getLogger(PayoutService::class.java)
    private val kenyaZone = ZoneId.of("Africa/Nairobi")

    // =====================================================
    // 💸 REQUEST PAYOUT (FINAL + SECURE)
    // =====================================================
    @Transactional
    fun requestPayout(
        landlordId: UUID,
        propertyId: UUID,
        amount: BigDecimal,
        pin: String
    ) {

        log.info("💸 Request payout → landlord=$landlordId property=$propertyId amount=$amount")

        // ===============================
        // ✅ BASIC VALIDATION
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
            throw BadRequestException("Unauthorized property access")
        }

        // =====================================================
        // 🔐 PIN VALIDATION (🔥 MUST COME FIRST)
        // =====================================================
        val wallet = walletRepository.findByPropertyId(propertyId)
            ?: throw BadRequestException("Wallet not found")

        if (wallet.pinHash.isNullOrBlank()) {
            throw BadRequestException("PIN not set")
        }

        val isValidPin = passwordEncoder.matches(pin, wallet.pinHash)

        log.info("🔐 PIN validation → property=$propertyId success=$isValidPin")

        if (!isValidPin) {
            throw BadRequestException("Invalid PIN")
        }

        // =====================================================
        // 🚫 PREVENT MULTIPLE REQUESTS (AFTER PIN)
        // =====================================================
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

        // =====================================================
        // 💰 BALANCE CALCULATION
        // =====================================================
        val balance = jdbcTemplate.queryForObject(
            """
            SELECT COALESCE(SUM(
                CASE
                    WHEN entry_type = 'CREDIT' THEN amount
                    WHEN entry_type = 'DEBIT' AND category = 'PAYOUT' THEN -amount
                    ELSE 0
                END
            ), 0)
            FROM ledger_entries
            WHERE property_id = ?
            """.trimIndent(),
            BigDecimal::class.java,
            propertyId
        ) ?: BigDecimal.ZERO

        log.info("💰 Balance → $balance")

        if (balance <= BigDecimal.ZERO) {
            throw BadRequestException("No funds available")
        }

        if (amount > balance) {
            throw BadRequestException("Insufficient balance")
        }

        // =====================================================
        // 💳 PAYOUT METHOD
        // =====================================================
        val payoutDetails = jdbcTemplate.queryForMap(
            "SELECT mpesa_phone, account_number FROM wallets WHERE property_id = ?",
            propertyId
        )

        val mpesa = payoutDetails["mpesa_phone"]?.toString()
        val bank = payoutDetails["account_number"]?.toString()

        val (method, destination) = when {
            !mpesa.isNullOrBlank() -> "MPESA" to mpesa
            !bank.isNullOrBlank() -> "BANK" to bank
            else -> throw BadRequestException("Complete payout setup first")
        }

        // =====================================================
        // 💾 SAVE PAYOUT REQUEST
        // =====================================================
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
    // 🔥 ADMIN MARK AS PAID
    // =====================================================
    @Transactional
    fun markAsPaid(
        payoutId: UUID,
        adminId: UUID,
        nationalId: String
    ) {

        log.info("🔥 Mark payout PAID → id=$payoutId")

        if (nationalId.isBlank()) {
            throw BadRequestException("National ID required")
        }

        val payout = jdbcTemplate.queryForMap(
            "SELECT * FROM payout_requests WHERE id = ? FOR UPDATE",
            payoutId
        )

        if (payout["status"] != "PENDING") {
            throw BadRequestException("Already processed")
        }

        val propertyId = UUID.fromString(payout["property_id"].toString())
        val amount = BigDecimal(payout["amount"].toString())

        // 🔐 VERIFY ADMIN ID
        val hash = jdbcTemplate.queryForObject(
            "SELECT national_id_hash FROM users WHERE id = ?",
            String::class.java,
            adminId
        ) ?: throw BadRequestException("Admin not configured")

        if (!passwordEncoder.matches(nationalId, hash)) {
            throw BadRequestException("Invalid National ID")
        }

        val now = LocalDateTime.now(kenyaZone)

        // 💰 WRITE LEDGER (SOURCE OF TRUTH)
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

        // ✅ UPDATE PAYOUT STATUS
        jdbcTemplate.update(
            """
            UPDATE payout_requests
            SET status = 'PAID',
                processed_at = ?,
                processed_by = ?
            WHERE id = ?
            """.trimIndent(),
            now,
            adminId,
            payoutId
        )

        log.info("✅ payout PAID → id=$payoutId")
    }

    // =====================================================
    // ❌ REJECT PAYOUT
    // =====================================================
    @Transactional
    fun rejectPayout(
        payoutId: UUID,
        adminId: UUID
    ) {

        log.info("❌ Reject payout → id=$payoutId")

        val payout = jdbcTemplate.queryForMap(
            "SELECT status FROM payout_requests WHERE id = ? FOR UPDATE",
            payoutId
        )

        if (payout["status"] != "PENDING") {
            throw BadRequestException("Already processed")
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