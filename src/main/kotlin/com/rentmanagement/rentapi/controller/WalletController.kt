package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.wallet.dto.WalletResponse
import com.rentmanagement.rentapi.wallet.dto.WalletTransaction
import com.rentmanagement.rentapi.services.WalletService
import org.springframework.web.bind.annotation.*
import java.math.BigDecimal
import java.util.UUID

@RestController
@RequestMapping("/api/properties")
class WalletController(

    private val walletService: WalletService

) {

    @GetMapping("/{propertyId}/wallet")
    fun getWallet(
        @PathVariable propertyId: UUID
    ): WalletResponse {

        return walletService.getWallet(propertyId)
    }

    @PostMapping("/{propertyId}/wallet/withdraw")
    fun withdraw(
        @PathVariable propertyId: UUID,
        @RequestParam amount: BigDecimal
    ): WalletResponse {

        return walletService.withdraw(propertyId, amount)
    }

    // ================================
    // WALLET TRANSACTIONS
    // ================================

    @GetMapping("/{propertyId}/wallet/transactions")
    fun transactions(
        @PathVariable propertyId: UUID
    ): List<WalletTransaction> {

        return walletService.getTransactions(propertyId)
    }

}