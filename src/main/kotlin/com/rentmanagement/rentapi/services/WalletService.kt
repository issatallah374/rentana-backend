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

    // ================================
    // GET WALLET
    // ================================

    fun getWallet(propertyId: UUID): WalletResponse {

        val property = propertyRepository
            .findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        val wallet = walletRepository.findByProperty(property)
            ?: walletRepository.save(
                Wallet(
                    property = property,
                    landlord = property.landlord,
                    balance = BigDecimal.ZERO
                )
            )

        return WalletResponse(
            balance = wallet.balance.toDouble(),
            totalCollected = wallet.balance.toDouble()
        )
    }

    // ================================
    // WITHDRAW
    // ================================

    fun withdraw(propertyId: UUID, amount: BigDecimal): WalletResponse {

        val property = propertyRepository
            .findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        val wallet = walletRepository.findByProperty(property)
            ?: throw RuntimeException("Wallet not found")

        if (amount < BigDecimal("600")) {
            throw RuntimeException("Minimum withdrawal is 600")
        }

        if (wallet.balance < amount) {
            throw RuntimeException("Insufficient funds")
        }

        wallet.balance = wallet.balance.subtract(amount)

        val saved = walletRepository.save(wallet)

        return WalletResponse(
            balance = saved.balance.toDouble(),
            totalCollected = saved.balance.toDouble()
        )
    }

    // ================================
    // WALLET TRANSACTION HISTORY
    // ================================

    fun getTransactions(propertyId: UUID): List<WalletTransaction> {

        val entries = ledgerEntryRepository
            .findWalletTransactions(propertyId)

        return entries.map {

            WalletTransaction(
                id = it.id!!,
                amount = it.amount,

                // convert enums to string
                entryType = it.entryType.name,

                category = it.category?.name,

                reference = null, // your LedgerEntry doesn't have reference

                createdAt = it.createdAt
            )
        }
    }

}