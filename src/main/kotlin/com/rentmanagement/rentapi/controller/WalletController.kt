package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransaction
import com.rentmanagement.rentapi.services.WalletService
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
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

    // ================================
    // 💰 GET WALLET
    // ================================
    @GetMapping("/{propertyId}/wallet")
    fun getWallet(
        @PathVariable propertyId: UUID
    ): WalletResponse {

        return walletService.getWallet(propertyId)
    }

    // ================================
    // 📒 TRANSACTIONS
    // ================================
    @GetMapping("/{propertyId}/wallet/transactions")
    fun transactions(
        @PathVariable propertyId: UUID
    ): List<WalletTransaction> {

        return walletService.getTransactions(propertyId)
    }

    // ================================
    // 🔒 SAVE PAYOUT DETAILS (SECURE)
    // ================================
    @PostMapping("/{propertyId}/wallet/payout/setup")
    fun savePayoutDetails(
        @PathVariable propertyId: UUID,
        @RequestBody data: Map<String, String>,
        authentication: Authentication
    ): String {

        val landlordId = UUID.fromString(authentication.name)

        val property = propertyRepository.findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        if (property.landlord.id != landlordId) {
            throw RuntimeException("Unauthorized")
        }

        val wallet = walletRepository.findByProperty(property)
            ?: walletRepository.save(
                com.rentmanagement.rentapi.models.Wallet(property = property)
            )

        val bankName = data["bankName"]?.trim()
        val accountNumber = data["accountNumber"]?.trim()
        val mpesaPhone = data["mpesaPhone"]?.trim()

        if (accountNumber.isNullOrBlank() && mpesaPhone.isNullOrBlank()) {
            throw RuntimeException("Provide bank or M-Pesa")
        }

        wallet.bankName = bankName
        wallet.accountNumber = accountNumber
        wallet.mpesaPhone = mpesaPhone

        walletRepository.save(wallet)

        return "Payout details saved"
    }
}