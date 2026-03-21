package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.Wallet
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransaction
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.util.UUID

@Service
class WalletService(

    private val walletRepository: WalletRepository,
    private val propertyRepository: PropertyRepository,
    private val ledgerEntryRepository: LedgerEntryRepository

) {

    // ===============================
    // 💰 GET WALLET (CORRECT)
    // ===============================
    fun getWallet(propertyId: UUID): WalletResponse {

        val property = propertyRepository
            .findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        val wallet = walletRepository.findByProperty(property)
            ?: walletRepository.save(Wallet(property = property))

        // ✅ TRUE BALANCE (ledger-based)
        val entries = ledgerEntryRepository.findWalletTransactions(propertyId)

        val balance = entries.fold(BigDecimal.ZERO) { acc, entry ->
            when (entry.entryType.name) {
                "CREDIT" -> acc + entry.amount
                "DEBIT" -> acc - entry.amount
                else -> acc
            }
        }

        // ✅ TOTAL COLLECTED (CORRECT)
        val totalCollected =
            ledgerEntryRepository.getTotalCollected(propertyId)

        val payoutSetupComplete =
            !wallet.accountNumber.isNullOrBlank() ||
                    !wallet.mpesaPhone.isNullOrBlank()

        return WalletResponse(
            balance = balance.toDouble(),
            totalCollected = totalCollected.toDouble(),
            payoutSetupComplete = payoutSetupComplete,
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