package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.Wallet
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransaction
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.util.UUID

@Service
class WalletService(

    private val walletRepository: WalletRepository,
    private val propertyRepository: PropertyRepository,
    private val ledgerEntryRepository: LedgerEntryRepository,
    private val jdbcTemplate: JdbcTemplate // ✅ added

) {

    // ===============================
    // 💰 GET WALLET (LEDGER-BASED)
    // ===============================
    fun getWallet(propertyId: UUID): WalletResponse {

        val property = propertyRepository
            .findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        val wallet = walletRepository.findByProperty(property)
            ?: walletRepository.save(
                Wallet(property = property)
            )

        // 🔥 TRUE BALANCE FROM LEDGER
        val balance = jdbcTemplate.queryForObject(
            """
            SELECT COALESCE(SUM(
                CASE
                    WHEN entry_type = 'CREDIT' THEN amount
                    WHEN entry_type = 'DEBIT' AND category = 'WITHDRAWAL' THEN -amount
                END
            ),0)
            FROM ledger_entries
            WHERE property_id = ?
            """.trimIndent(),
            BigDecimal::class.java,
            propertyId
        ) ?: BigDecimal.ZERO

        // 🔥 TOTAL COLLECTED (ONLY CREDITS)
        val totalCollected = jdbcTemplate.queryForObject(
            """
            SELECT COALESCE(SUM(amount),0)
            FROM ledger_entries
            WHERE property_id = ?
            AND entry_type = 'CREDIT'
            """.trimIndent(),
            BigDecimal::class.java,
            propertyId
        ) ?: BigDecimal.ZERO

        val payoutSetupComplete =
            !wallet.accountNumber.isNullOrBlank() ||
                    !wallet.mpesaPhone.isNullOrBlank()

        return WalletResponse(
            balance = balance.toDouble(),
            totalCollected = totalCollected.toDouble(),
            payoutSetupComplete = payoutSetupComplete,

            // ✅ payout details (needed by Android)
            mpesaPhone = wallet.mpesaPhone,
            accountNumber = wallet.accountNumber,
            bankName = wallet.bankName
        )
    }

    // ===============================
    // 📒 TRANSACTIONS
    // ===============================
    fun getTransactions(propertyId: UUID): List<WalletTransaction> {

        val entries = ledgerEntryRepository.findWalletTransactions(propertyId)

        return entries.map {
            WalletTransaction(
                id = it.id!!,
                amount = it.amount,
                entryType = it.entryType.name,
                category = it.category?.name,
                reference = it.reference,
                createdAt = it.createdAt
            )
        }
    }
}