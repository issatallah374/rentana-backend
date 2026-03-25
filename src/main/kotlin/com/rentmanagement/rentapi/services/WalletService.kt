package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.Wallet
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.dto.SetWalletPinRequest
import com.rentmanagement.rentapi.wallet.dto.WalletTransactionResponse
import org.slf4j.LoggerFactory
import com.rentmanagement.rentapi.dto.ForgotPinRequest
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.UUID
import com.rentmanagement.rentapi.dto.ResetPinRequest

@Service
class WalletService(

    private val propertyRepository: PropertyRepository,
    private val ledgerEntryRepository: LedgerEntryRepository,
    private val walletRepository: WalletRepository,
    private val passwordEncoder: PasswordEncoder

) {

    private val log = LoggerFactory.getLogger(WalletService::class.java)

    private val otpStore = mutableMapOf<UUID, String>()

    private val kenyaZone = ZoneId.of("Africa/Nairobi")
    private val formatter = DateTimeFormatter.ofPattern("dd MMM yyyy, hh:mm a")

    // =====================================================
    // 💰 GET WALLET (FINAL FIXED VERSION)
    // =====================================================
    fun getWallet(propertyId: UUID): WalletResponse {

        return try {

            log.info("💰 Loading wallet → property=$propertyId")

            // ✅ Validate property
            val property = propertyRepository.findById(propertyId)
                .orElseThrow { RuntimeException("Property not found") }

            // =====================================================
            // 🔥 CRITICAL FIX (USE ID NOT ENTITY)
            // =====================================================
            val wallet = walletRepository.findByPropertyId(propertyId)
                ?: walletRepository.save(
                    Wallet(property = property)
                )

            val mpesaPhone = wallet.mpesaPhone
            val accountNumber = wallet.accountNumber
            val bankName = wallet.bankName

            log.info("🏦 Wallet → account=$accountNumber mpesa=$mpesaPhone")

            // =====================================================
            // 🏦 PAYOUT STATUS
            // =====================================================
            val payoutSetupComplete =
                !accountNumber.isNullOrBlank() ||
                        !mpesaPhone.isNullOrBlank()

            // =====================================================
            // 📒 FETCH LEDGER ENTRIES
            // =====================================================
            val entries = ledgerEntryRepository.findWalletTransactions(propertyId)

            log.info("📒 Ledger entries = ${entries.size}")

            // =====================================================
            // 💰 BALANCE CALCULATION (STRICT + CORRECT)
            // =====================================================
            val rawBalance = entries.fold(BigDecimal.ZERO) { acc, entry ->

                val amount = entry.amount ?: BigDecimal.ZERO
                val type = entry.entryType?.name
                val category = entry.category?.name

                when {
                    // ✅ REAL MONEY IN
                    type == "CREDIT" && category == "RENT_PAYMENT" ->
                        acc.add(amount)

                    // ✅ REAL MONEY OUT
                    type == "DEBIT" && category == "PAYOUT" ->
                        acc.subtract(amount)

                    // ❌ IGNORE RENT_CHARGE + noise
                    else -> acc
                }
            }

            val safeBalance = rawBalance
                .max(BigDecimal.ZERO)
                .setScale(2, RoundingMode.HALF_UP)

            // =====================================================
            // 📊 TOTAL COLLECTED
            // =====================================================
            val totalCollected =
                ledgerEntryRepository.getTotalCollected(propertyId)
                    ?.setScale(2, RoundingMode.HALF_UP)
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

    fun setWalletPin(request: SetWalletPinRequest) {

        val wallet = walletRepository.findByPropertyId(request.propertyId)
            ?: throw RuntimeException("Wallet not found")

        if (request.pin.length < 4) {
            throw RuntimeException("PIN must be at least 4 digits")
        }

        wallet.pinHash = passwordEncoder.encode(request.pin)
        wallet.nationalId = request.nationalId
        wallet.phoneNumber = request.phoneNumber

        walletRepository.save(wallet)
    }

    fun requestPinResetOtp(request: ForgotPinRequest) {

        val wallet = walletRepository.findByNationalId(request.nationalId)
            ?: throw RuntimeException("Invalid National ID")

        if (wallet.phoneNumber.isNullOrBlank()) {
            throw RuntimeException("No phone linked to wallet")
        }

        val otp = (100000..999999).random().toString()

        otpStore[wallet.id!!] = otp

        log.info("📱 OTP generated → ${wallet.phoneNumber} → $otp")

        // 🔥 TODO: Replace with real SMS
        smsService.sendSms(wallet.phoneNumber!!, "Your OTP is $otp")
    }

    fun resetPin(request: ResetPinRequest) {

        val wallet = walletRepository.findByNationalId(request.nationalId)
            ?: throw RuntimeException("Invalid National ID")

        val savedOtp = otpStore[wallet.id!!]

        if (savedOtp != request.otp) {
            throw RuntimeException("Invalid OTP")
        }

        if (request.newPin.length < 4) {
            throw RuntimeException("PIN must be at least 4 digits")
        }

        wallet.pinHash = passwordEncoder.encode(request.newPin)

        walletRepository.save(wallet)

        otpStore.remove(wallet.id!!)

        log.info("✅ PIN reset successful → wallet=${wallet.id}")
    }



    // =====================================================
    // 📒 GET TRANSACTIONS
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