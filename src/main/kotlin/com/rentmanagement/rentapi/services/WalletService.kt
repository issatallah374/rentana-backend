package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.Wallet
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransactionResponse
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

@Service
class WalletService(

    private val walletRepository: WalletRepository,
    private val propertyRepository: PropertyRepository,
    private val ledgerEntryRepository: LedgerEntryRepository

) {

    // 🇰🇪 KENYA TIMEZONE
    private val kenyaZone = ZoneId.of("Africa/Nairobi")

    private val formatter = DateTimeFormatter.ofPattern("dd MMM yyyy, hh:mm a")

    // ===============================
    // 💰 GET WALLET
    // ===============================
    fun getWallet(propertyId: UUID): WalletResponse {

        val property = propertyRepository
            .findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        val wallet = walletRepository.findByProperty(property)
            ?: walletRepository.save(Wallet(property = property))

        val entries =
            ledgerEntryRepository.findWalletTransactions(propertyId)

        // ✅ BALANCE (SAFE + CLEAN)
        val balance = entries.fold(BigDecimal.ZERO) { acc, entry ->

            val amount = entry.amount ?: BigDecimal.ZERO

            when (entry.entryType?.name) {
                "CREDIT" -> acc + amount
                "DEBIT" -> acc - amount
                else -> acc
            }
        }

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

        return ledgerEntryRepository
            .findWalletTransactions(propertyId)
            .map { entry ->

                val kenyaTime = entry.createdAt
                    ?.atZone(ZoneId.systemDefault())
                    ?.withZoneSameInstant(kenyaZone)

                WalletTransactionResponse(
                    id = entry.id?.toString() ?: "",
                    amount = entry.amount?.toDouble() ?: 0.0,
                    entryType = entry.entryType?.name ?: "UNKNOWN",
                    category = entry.category?.name,
                    reference = entry.reference,

                    // 🇰🇪 BEAUTIFUL KENYAN TIME
                    createdAt = kenyaTime?.format(formatter) ?: ""
                )
            }
    }
}