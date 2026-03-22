package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.Wallet
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransactionResponse
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.time.format.DateTimeFormatter
import java.util.UUID

@Service
class WalletService(

    private val walletRepository: WalletRepository,
    private val propertyRepository: PropertyRepository,
    private val ledgerEntryRepository: LedgerEntryRepository

) {

    // ===============================
    // 💰 GET WALLET
    // ===============================
    fun getWallet(propertyId: UUID): WalletResponse {

        val property = propertyRepository
            .findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        // Ensure wallet exists
        val wallet = walletRepository.findByProperty(property)
            ?: walletRepository.save(Wallet(property = property))

        // Fetch ledger entries
        val entries =
            ledgerEntryRepository.findWalletTransactions(propertyId)

        // ✅ SAFE BALANCE CALCULATION
        val balance = entries.fold(BigDecimal.ZERO) { acc, entry ->

            val amount = entry.amount ?: BigDecimal.ZERO

            when (entry.entryType?.name) {
                "CREDIT" -> acc + amount
                "DEBIT" -> acc - amount
                else -> acc
            }
        }

        // ✅ TOTAL COLLECTED (SAFE)
        val totalCollected =
            ledgerEntryRepository.getTotalCollected(propertyId)
                ?: BigDecimal.ZERO

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
    // 📒 GET TRANSACTIONS
    // ===============================

    fun getTransactions(propertyId: UUID): List<WalletTransactionResponse> {

        val formatter = DateTimeFormatter.ISO_LOCAL_DATE_TIME

        return ledgerEntryRepository
            .findWalletTransactions(propertyId)
            .map { entry ->

                WalletTransactionResponse(
                    id = entry.id?.toString() ?: "",
                    amount = entry.amount?.toDouble() ?: 0.0,
                    entryType = entry.entryType?.name ?: "UNKNOWN",
                    category = entry.category?.name,
                    reference = entry.reference,
                    createdAt = entry.createdAt
                        ?.format(formatter)
                        ?: ""
                )
            }
    }
}