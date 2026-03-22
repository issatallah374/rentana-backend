package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransactionResponse
import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID

@Service
class WalletService(

    private val propertyRepository: PropertyRepository,
    private val ledgerEntryRepository: LedgerEntryRepository,
    private val jdbcTemplate: JdbcTemplate

) {

    private val log = LoggerFactory.getLogger(WalletService::class.java)

    private val kenyaZone = ZoneId.of("Africa/Nairobi")
    private val formatter = DateTimeFormatter.ofPattern("dd MMM yyyy, hh:mm a")

    // =====================================================
    // 💰 GET WALLET (FINAL BANK-GRADE VERSION)
    // =====================================================
    fun getWallet(propertyId: UUID): WalletResponse {

        return try {

            log.info("💰 Loading wallet → property=$propertyId")

            // ✅ Validate property exists
            propertyRepository.findById(propertyId)
                .orElseThrow { RuntimeException("Property not found") }

            // =====================================================
            // 🔥 READ WALLET DIRECTLY FROM DB (NO JPA BUGS)
            // =====================================================
            val walletRow = jdbcTemplate.queryForList(
                """
                SELECT mpesa_phone, account_number, bank_name
                FROM wallets
                WHERE property_id = ?
                """.trimIndent(),
                propertyId
            ).firstOrNull()

            val mpesaPhone = walletRow?.get("mpesa_phone")?.toString()
            val accountNumber = walletRow?.get("account_number")?.toString()
            val bankName = walletRow?.get("bank_name")?.toString()

            log.info("🏦 Wallet → account=$accountNumber mpesa=$mpesaPhone")

            // =====================================================
            // 🏦 PAYOUT STATUS (THIS FIXES YOUR UI ISSUE)
            // =====================================================
            val payoutSetupComplete =
                !accountNumber.isNullOrBlank() ||
                        !mpesaPhone.isNullOrBlank()

            // =====================================================
            // 📒 FETCH LEDGER ENTRIES
            // =====================================================
            val entries =
                ledgerEntryRepository.findWalletTransactions(propertyId)

            log.info("📒 Ledger entries = ${entries.size}")

            // =====================================================
            // 💰 BALANCE CALCULATION (CORRECT + SAFE)
            // =====================================================
            val rawBalance = entries.fold(BigDecimal.ZERO) { acc, entry ->

                val amount = entry.amount ?: BigDecimal.ZERO
                val type = entry.entryType?.name
                val category = entry.category?.name

                when {
                    // ✅ ONLY REAL MONEY IN
                    type == "CREDIT" && category == "RENT_PAYMENT" -> acc.add(amount)

                    // ✅ ONLY REAL MONEY OUT
                    type == "DEBIT" && category == "PAYOUT" -> acc.subtract(amount)

                    // ❌ IGNORE RENT_CHARGE + EVERYTHING ELSE
                    else -> acc
                }
            }

            val safeBalance = rawBalance
                .max(BigDecimal.ZERO)
                .setScale(2, java.math.RoundingMode.HALF_UP)

            // =====================================================
            // 📊 TOTAL COLLECTED (ONLY RENT PAYMENTS)
            // =====================================================
            val totalCollected =
                ledgerEntryRepository.getTotalCollected(propertyId)
                    ?: BigDecimal.ZERO

            log.info("💰 Balance=$safeBalance collected=$totalCollected")

            // =====================================================
            // ✅ FINAL RESPONSE
            // =====================================================
            WalletResponse(
                balance = safeBalance.toDouble(),
                totalCollected = totalCollected.toDouble(),
                payoutSetupComplete = payoutSetupComplete,
                mpesaPhone = mpesaPhone,
                accountNumber = accountNumber,
                bankName = bankName
            )

        } catch (e: Exception) {

            log.error("❌ Wallet load failed → property=$propertyId", e)

            // 🔥 NEVER BREAK FRONTEND
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

    // =====================================================
    // 📒 GET TRANSACTIONS (SAFE + CLEAN)
    // =====================================================
    fun getTransactions(propertyId: UUID): List<WalletTransactionResponse> {

        return try {

            log.info("📒 Loading transactions → property=$propertyId")

            ledgerEntryRepository
                .findWalletTransactions(propertyId)
                .map { entry ->

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

            log.error("❌ Transactions failed → property=$propertyId", e)

            emptyList()
        }
    }
}