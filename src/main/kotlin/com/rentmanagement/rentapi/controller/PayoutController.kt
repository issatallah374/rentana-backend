package com.rentmanagement.rentapi.controllers

import com.rentmanagement.rentapi.services.PayoutService
import org.slf4j.LoggerFactory
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import java.math.BigDecimal
import java.util.*

@RestController
@RequestMapping("/api/payouts")
class PayoutController(
    private val payoutService: PayoutService,
    private val propertyRepository: PropertyRepository,
    private val walletRepository: WalletRepository
) {

    private val log = LoggerFactory.getLogger(PayoutController::class.java)

    // =====================================================
    // 💸 REQUEST PAYOUT
    // =====================================================
    @PostMapping("/request")
    fun requestPayout(
        @RequestParam propertyId: UUID,
        @RequestParam amount: BigDecimal,
        authentication: Authentication?
    ): ResponseEntity<String> {

        if (authentication == null || authentication.name.isNullOrBlank()) {
            throw RuntimeException("Unauthorized")
        }

        val landlordId = UUID.fromString(authentication.name)

        val property = propertyRepository.findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        // 🔐 ownership check
        if (property.landlord.id != landlordId) {
            throw RuntimeException("Unauthorized")
        }

        val wallet = walletRepository.findByProperty(property)
            ?: throw RuntimeException("Wallet not found")

        // 🔒 enforce payout setup
        if (wallet.accountNumber.isNullOrBlank() && wallet.mpesaPhone.isNullOrBlank()) {
            throw RuntimeException("Complete payout setup first")
        }

        log.info("💸 Payout request → landlord=$landlordId property=$propertyId amount=$amount")

        payoutService.requestPayout(
            landlordId = landlordId,
            propertyId = propertyId,
            amount = amount
        )

        return ResponseEntity.ok("Payout requested")
    }

    // =====================================================
    // 🔥 ADMIN MARK AS PAID
    // =====================================================
    @PostMapping("/{id}/mark-paid")
    fun markPaid(
        @PathVariable id: UUID,
        authentication: Authentication?
    ): ResponseEntity<String> {

        if (authentication == null) throw RuntimeException("Unauthorized")

        val roles = authentication.authorities.map { it.authority }

        if (!roles.contains("ROLE_ADMIN")) {
            throw RuntimeException("Forbidden")
        }

        payoutService.markAsPaid(id)

        return ResponseEntity.ok("Marked as paid")
    }

    // =====================================================
    // ❌ ADMIN REJECT
    // =====================================================
    @PostMapping("/{id}/reject")
    fun rejectPayout(
        @PathVariable id: UUID,
        authentication: Authentication?
    ): ResponseEntity<String> {

        if (authentication == null) throw RuntimeException("Unauthorized")

        val roles = authentication.authorities.map { it.authority }

        if (!roles.contains("ROLE_ADMIN")) {
            throw RuntimeException("Forbidden")
        }

        payoutService.rejectPayout(id)

        return ResponseEntity.ok("Payout rejected")
    }
}