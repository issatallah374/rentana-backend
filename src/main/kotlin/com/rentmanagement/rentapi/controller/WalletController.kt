package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransaction
import com.rentmanagement.rentapi.services.WalletService
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import com.rentmanagement.rentapi.models.Wallet
import org.slf4j.LoggerFactory
import com.rentmanagement.rentapi.dto.PayoutSetupRequest

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

    // ================================
    // 💰 GET WALLET
    // ================================
    @GetMapping("/{propertyId}/wallet")
    fun getWallet(@PathVariable propertyId: UUID): WalletResponse {
        return walletService.getWallet(propertyId)
    }

    // ================================
    // 📒 TRANSACTIONS
    // ================================
    @GetMapping("/{propertyId}/wallet/transactions")
    fun transactions(@PathVariable propertyId: UUID): List<WalletTransaction> {
        return walletService.getTransactions(propertyId)
    }

    // ================================
    // 🔒 SAVE PAYOUT DETAILS
    // ================================
    @PostMapping("/{propertyId}/wallet/payout/setup")
    fun savePayoutDetails(
        @PathVariable propertyId: UUID,
        @RequestBody request: PayoutSetupRequest,
        authentication: Authentication
    ): String {

        val landlordId = UUID.fromString(authentication.name)

        val property = propertyRepository.findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        if (property.landlord.id != landlordId) {
            log.warn("❌ Unauthorized payout setup attempt")
            throw RuntimeException("Unauthorized")
        }

        val wallet = walletRepository.findByProperty(property)
            ?: walletRepository.save(Wallet(property = property))

        // validation
        if (request.accountNumber.isNullOrBlank() && request.mpesaPhone.isNullOrBlank()) {
            throw RuntimeException("Provide bank account or M-Pesa phone")
        }

        // optional: normalize phone
        val phone = request.mpesaPhone?.replace("\\s".toRegex(), "")

        wallet.bankName = request.bankName?.trim()
        wallet.accountNumber = request.accountNumber?.trim()
        wallet.mpesaPhone = phone

        walletRepository.save(wallet)

        // ✅ mark property as configured
        property.payoutSetupComplete = true
        propertyRepository.save(property)

        log.info("✅ Payout setup saved for property=$propertyId")

        return "Payout details saved"
    }
}