package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.exceptions.BadRequestException
import com.rentmanagement.rentapi.repository.WalletRepository
import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.math.BigDecimal
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.*

@Service
class PayoutService(
    private val jdbcTemplate: JdbcTemplate,
    private val walletRepository: WalletRepository,
    private val passwordEncoder: PasswordEncoder
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
        amount: BigDecimal,
        pin: String
    ) {

        log.info(
            "💸 Request payout → landlord={} property={} amount={}",
            landlordId,
            propertyId,
            amount
        )

        // =====================================================
        // ✅ BASIC VALIDATION
        // =====================================================

        if (amount <= BigDecimal.ZERO) {
            throw BadRequestException("Enter a valid amount")
        }

        if (amount < BigDecimal("3")) {
            throw BadRequestException("Minimum withdrawal is KES 3")
        }

        // =====================================================
        // 🔐 VERIFY PROPERTY OWNERSHIP
        // =====================================================

        val ownsProperty = jdbcTemplate.queryForObject(
            """
            SELECT COUNT(*)
            FROM properties
            WHERE id = ?
            AND landlord_id = ?
            """.trimIndent(),
            Int::class.java,
            propertyId,
            landlordId
        ) ?: 0

        if (ownsProperty == 0) {
            throw BadRequestException("Unauthorized property access")
        }

        // =====================================================
        // 🔐 VERIFY WALLET + PIN
        // =====================================================

        val wallet = walletRepository.findByPropertyId(propertyId)
            ?: throw BadRequestException("Wallet not found")

        if (wallet.pinHash.isNullOrBlank()) {
            throw BadRequestException("PIN not set")
        }

        val validPin = passwordEncoder.matches(
            pin,
            wallet.pinHash
        )

        log.info(
            "🔐 PIN validation → property={} success={}",
            propertyId,
            validPin
        )

        if (!validPin) {
            throw BadRequestException("Invalid PIN")
        }

        // =====================================================
        // 🚫 PREVENT MULTIPLE PENDING PAYOUTS
        // =====================================================

        val pending = jdbcTemplate.queryForObject(
            """
            SELECT COUNT(*)
            FROM payout_requests
            WHERE property_id = ?
            AND status = 'PENDING'
            """.trimIndent(),
            Int::class.java,
            propertyId
        ) ?: 0

        if (pending > 0) {
            throw BadRequestException(
                "You already have a pending payout"
            )
        }

        // =====================================================
        // 💰 CALCULATE AVAILABLE BALANCE
        // =====================================================

        val balance = jdbcTemplate.queryForObject(
            """
            SELECT COALESCE(SUM(
                CASE
                    WHEN entry_type = 'CREDIT'
                        THEN amount

                    WHEN entry_type = 'DEBIT'
                        AND category = 'PAYOUT'
                        THEN -amount

                    ELSE 0
                END
            ), 0)
            FROM ledger_entries
            WHERE property_id = ?
            """.trimIndent(),
            BigDecimal::class.java,
            propertyId
        ) ?: BigDecimal.ZERO

        log.info("💰 Available balance → {}", balance)

        if (balance <= BigDecimal.ZERO) {
            throw BadRequestException("No funds available")
        }

        if (amount > balance) {
            throw BadRequestException("Insufficient balance")
        }

        // =====================================================
        // 💳 DETERMINE PAYOUT METHOD
        // =====================================================

        val payoutDetails = jdbcTemplate.queryForMap(
            """
            SELECT
                mpesa_phone,
                account_number
            FROM wallets
            WHERE property_id = ?
            """.trimIndent(),
            propertyId
        )

        val mpesaPhone =
            payoutDetails["mpesa_phone"]?.toString()

        val bankAccount =
            payoutDetails["account_number"]?.toString()

        val (method, destination) = when {

            !mpesaPhone.isNullOrBlank() ->
                "MPESA" to mpesaPhone

            !bankAccount.isNullOrBlank() ->
                "BANK" to bankAccount

            else ->
                throw BadRequestException(
                    "Complete payout setup first"
                )
        }

        // =====================================================
        // 💾 SAVE PAYOUT REQUEST
        // =====================================================

        val now = LocalDateTime.now(kenyaZone)

        val payoutId = UUID.randomUUID()

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
            VALUES (
                ?, ?, ?, ?, ?, ?, 'PENDING', ?
            )
            """.trimIndent(),
            payoutId,
            landlordId,
            propertyId,
            amount,
            method,
            destination,
            now
        )

        log.info(
            "✅ payout request created → id={} method={} destination={}",
            payoutId,
            method,
            destination
        )
    }

    // =====================================================
    // 🔥 ADMIN MARK PAYOUT AS PAID
    // =====================================================
    @Transactional
    fun markAsPaid(
        payoutId: UUID,
        adminId: UUID,
        nationalId: String
    ) {

        log.info("🔥 Mark payout PAID → id={}", payoutId)

        if (nationalId.isBlank()) {
            throw BadRequestException(
                "National ID required"
            )
        }

        // =====================================================
        // 🔒 LOCK PAYOUT ROW
        // =====================================================

        val payout = jdbcTemplate.queryForMap(
            """
            SELECT *
            FROM payout_requests
            WHERE id = ?
            FOR UPDATE
            """.trimIndent(),
            payoutId
        )

        val status = payout["status"]?.toString()

        if (status != "PENDING") {
            throw BadRequestException(
                "Already processed"
            )
        }

        val propertyId = UUID.fromString(
            payout["property_id"].toString()
        )

        val amount = BigDecimal(
            payout["amount"].toString()
        )

        // =====================================================
        // 🔐 VERIFY ADMIN NATIONAL ID
        // =====================================================

        val nationalIdHash = jdbcTemplate.queryForObject(
            """
            SELECT national_id_hash
            FROM users
            WHERE id = ?
            """.trimIndent(),
            String::class.java,
            adminId
        ) ?: throw BadRequestException(
            "Admin not configured"
        )

        val validNationalId = passwordEncoder.matches(
            nationalId,
            nationalIdHash
        )

        if (!validNationalId) {
            throw BadRequestException(
                "Invalid National ID"
            )
        }

        // =====================================================
        // 🕒 CURRENT TIME
        // =====================================================

        val now = LocalDateTime.now(kenyaZone)

        // =====================================================
        // 💰 CREATE IMMUTABLE LEDGER ENTRY
        // =====================================================

        jdbcTemplate.update(
            """
            INSERT INTO ledger_entries(
                property_id,
                tenancy_id,
                entry_type,
                category,
                amount,
                reference,
                reference_id,
                entry_month,
                entry_year,
                created_at
            )
            VALUES (
                ?,
                NULL,
                'DEBIT',
                'PAYOUT',
                ?,
                ?,
                ?,
                ?,
                ?,
                ?
            )
            """.trimIndent(),
            propertyId,
            amount,
            "PAYOUT:$payoutId",
            payoutId,
            now.monthValue,
            now.year,
            now
        )

        // =====================================================
        // ✅ UPDATE PAYOUT STATUS
        // =====================================================

        jdbcTemplate.update(
            """
            UPDATE payout_requests
            SET
                status = 'PAID',
                processed_at = ?,
                processed_by = ?
            WHERE id = ?
            """.trimIndent(),
            now,
            adminId,
            payoutId
        )

        log.info(
            "✅ payout marked PAID → id={} amount={}",
            payoutId,
            amount
        )
    }

    // =====================================================
    // ❌ REJECT PAYOUT
    // =====================================================
    @Transactional
    fun rejectPayout(
        payoutId: UUID,
        adminId: UUID
    ) {

        log.info(
            "❌ Reject payout → id={}",
            payoutId
        )

        // =====================================================
        // 🔒 LOCK PAYOUT ROW
        // =====================================================

        val payout = jdbcTemplate.queryForMap(
            """
            SELECT status
            FROM payout_requests
            WHERE id = ?
            FOR UPDATE
            """.trimIndent(),
            payoutId
        )

        val status = payout["status"]?.toString()

        if (status != "PENDING") {
            throw BadRequestException(
                "Already processed"
            )
        }

        val now = LocalDateTime.now(kenyaZone)

        // =====================================================
        // ❌ MARK REJECTED
        // =====================================================

        jdbcTemplate.update(
            """
            UPDATE payout_requests
            SET
                status = 'REJECTED',
                processed_at = ?,
                processed_by = ?
            WHERE id = ?
            """.trimIndent(),
            now,
            adminId,
            payoutId
        )

        log.info(
            "✅ payout rejected → id={}",
            payoutId
        )
    }
}