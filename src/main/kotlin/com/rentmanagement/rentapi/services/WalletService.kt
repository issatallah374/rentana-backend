package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.Wallet
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransactionResponse
import org.slf4j.LoggerFactory
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

    private val log = LoggerFactory.getLogger(WalletService::class.java)

    // 🇰🇪 Kenya timezone
    private val kenyaZone = ZoneId.of("Africa/Nairobi")

    // 🕒 Clean Kenyan format
    private val formatter = DateTimeFormatter.ofPattern("dd MMM yyyy, hh:mm a")

    // ===============================
    // 💰 GET WALLET
    // ===============================
    fun getWallet(propertyId: UUID): WalletResponse {

        return try {

            val property = propertyRepository
                .findById(propertyId)
                .orElseThrow { RuntimeException("Property not found") }

            val wallet = walletRepository.findByProperty(property)
                ?: walletRepository.save(Wallet(property = property))

            val entries =
                ledgerEntryRepository.findWalletTransactions(propertyId)

            // ✅ CORRECT BALANCE (handles PAYOUT too)
            val rawBalance = entries.fold(BigDecimal.ZERO) { acc, entry ->

                val amount = entry.amount ?: BigDecimal.ZERO

                when (entry.entryType?.name) {
                    "CREDIT" -> acc + amount
                    "DEBIT" -> acc - amount
                    else -> acc
                }
            }

            // 🔥 NEVER RETURN NEGATIVE (fixes UI crash)
            val safeBalance = rawBalance.max(BigDecimal.ZERO)

            val totalCollected =
                ledgerEntryRepository.getTotalCollected(propertyId)
                    ?: BigDecimal.ZERO

            val payoutSetupComplete =
                !wallet.accountNumber.isNullOrBlank() ||
                        !wallet.mpesaPhone.isNullOrBlank()

            WalletResponse(
                balance = safeBalance.toDouble(),
                totalCollected = totalCollected.toDouble(),
                payoutSetupComplete = payoutSetupComplete,
                mpesaPhone = wallet.mpesaPhone,
                accountNumber = wallet.accountNumber,
                bankName = wallet.bankName
            )

        } catch (e: Exception) {

            log.error("❌ Wallet load failed → property=$propertyId", e)

            // 🔥 Always return safe response (NO 500)
            WalletResponse(
                balance = 0.0,
                totalCollected = 0.0,
                payoutSetupComplete = false,
                mpesaPhone = null,
                accountNumber = null,
                bankName = null
            )
        }
    }

    // ===============================
    // 📒 GET TRANSACTIONS
    // ===============================
    fun getTransactions(propertyId: UUID): List<WalletTransactionResponse> {

        return try {

            ledgerEntryRepository
                .findWalletTransactions(propertyId)
                .map { entry ->

                    // 🇰🇪 SAFE TIME CONVERSION
                    val formattedTime = try {

                        entry.createdAt
                            ?.atZone(ZoneId.systemDefault())
                            ?.withZoneSameInstant(kenyaZone)
                            ?.format(formatter)

                    } catch (e: Exception) {
                        "—"
                    }

                    WalletTransactionResponse(
                        id = entry.id?.toString() ?: "",
                        amount = entry.amount?.toDouble() ?: 0.0,
                        entryType = entry.entryType?.name ?: "UNKNOWN",
                        category = entry.category?.name ?: "—",
                        reference = entry.reference ?: "—",
                        createdAt = formattedTime ?: "—"
                    )
                }

        } catch (e: Exception) {

            log.error("❌ Transactions load failed → property=$propertyId", e)

            // 🔥 NEVER BREAK FRONTEND
            emptyList()
        }
    }
}