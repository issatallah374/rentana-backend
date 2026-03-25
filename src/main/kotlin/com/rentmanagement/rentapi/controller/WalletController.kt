package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransactionResponse
import com.rentmanagement.rentapi.services.WalletService
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import com.rentmanagement.rentapi.models.Wallet
import com.rentmanagement.rentapi.dto.*
import org.slf4j.LoggerFactory
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import java.util.UUID

@RestController
@RequestMapping("/api/properties")
class WalletController(

    private val walletService: WalletService,
    private val walletRepository: WalletRepository,
    private val propertyRepository: PropertyRepository

) {

    private val log = LoggerFactory.getLogger(WalletController::class.java)

    // =====================================================
    // 💰 GET WALLET
    // =====================================================
    @GetMapping("/{propertyId}/wallet")
    fun getWallet(@PathVariable propertyId: UUID): WalletResponse {
        return walletService.getWallet(propertyId)
    }

    // =====================================================
    // 📒 TRANSACTIONS
    // =====================================================
    @GetMapping("/{propertyId}/wallet/transactions")
    fun transactions(@PathVariable propertyId: UUID): List<WalletTransactionResponse> {
        return walletService.getTransactions(propertyId)
    }

    // =====================================================
    // 🔐 SET PIN (🔥 FIXED ENDPOINT)
    // =====================================================
    @PostMapping("/wallet/set-pin")
    fun setPin(
        @RequestBody request: SetWalletPinRequest,
        authentication: Authentication?
    ): ResponseEntity<Any> {

        if (authentication == null || authentication.name.isNullOrBlank()) {
            throw RuntimeException("Unauthorized")
        }

        val landlordId = UUID.fromString(authentication.name)

        val property = propertyRepository.findById(request.propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        if (property.landlord.id != landlordId) {
            throw RuntimeException("Unauthorized")
        }

        walletService.setWalletPin(request)

        log.info("🔐 PIN set → property=${request.propertyId}")

        return ResponseEntity.ok(mapOf("message" to "PIN set successfully"))
    }

    // =====================================================
    // 📱 FORGOT PIN (OTP)
    // =====================================================
    @PostMapping("/wallet/forgot-pin")
    fun forgotPin(
        @RequestBody request: ForgotPinRequest
    ): ResponseEntity<Any> {

        walletService.requestPinResetOtp(request)

        return ResponseEntity.ok(mapOf("message" to "OTP sent"))
    }

    // =====================================================
    // 🔄 RESET PIN
    // =====================================================
    @PostMapping("/wallet/reset-pin")
    fun resetPin(
        @RequestBody request: ResetPinRequest
    ): ResponseEntity<Any> {

        walletService.resetPin(request)

        return ResponseEntity.ok(mapOf("message" to "PIN reset successful"))
    }

    // =====================================================
    // 🏦 SAVE PAYOUT DETAILS
    // =====================================================
    @PostMapping("/{propertyId}/wallet/payout/setup")
    fun savePayoutDetails(
        @PathVariable propertyId: UUID,
        @RequestBody request: PayoutSetupRequest,
        authentication: Authentication?
    ): ResponseEntity<String> {

        if (authentication == null || authentication.name.isNullOrBlank()) {
            throw RuntimeException("Unauthorized")
        }

        val landlordId = UUID.fromString(authentication.name)

        val property = propertyRepository.findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        if (property.landlord.id != landlordId) {
            log.warn("❌ Unauthorized payout setup attempt")
            throw RuntimeException("Unauthorized")
        }

        val wallet = walletRepository.findByPropertyId(propertyId)
            ?: walletRepository.save(Wallet(property = property))

        if (request.accountNumber.isNullOrBlank() && request.mpesaPhone.isNullOrBlank()) {
            throw RuntimeException("Provide bank account or M-Pesa phone")
        }

        val phone = request.mpesaPhone
            ?.replace("\\s".toRegex(), "")
            ?.replaceFirst("^0".toRegex(), "254")

        wallet.bankName = request.bankName?.trim()
        wallet.accountNumber = request.accountNumber?.trim()
        wallet.mpesaPhone = phone

        walletRepository.save(wallet)

        property.payoutSetupComplete = true
        propertyRepository.save(property)

        log.info("✅ Payout setup saved → property=$propertyId")

        return ResponseEntity.ok("Payout details saved")
    }
}