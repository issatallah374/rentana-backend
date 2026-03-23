package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import com.rentmanagement.rentapi.services.PayoutService
import org.slf4j.LoggerFactory
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
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
    // 🔐 HELPERS
    // =====================================================
    private fun requireUser(auth: Authentication?): UUID {
        if (auth == null || auth.name.isNullOrBlank()) {
            throw RuntimeException("Unauthorized")
        }
        return UUID.fromString(auth.name)
    }

    private fun requireAdmin(auth: Authentication?): UUID {
        val userId = requireUser(auth)
        val roles = auth!!.authorities.map { it.authority }

        if (!roles.contains("ROLE_ADMIN")) {
            throw RuntimeException("Forbidden")
        }

        return userId
    }

    // =====================================================
    // 💸 REQUEST PAYOUT
    // =====================================================
    @PostMapping("/request")
    fun requestPayout(
        @RequestParam propertyId: UUID,
        @RequestParam amount: BigDecimal,
        auth: Authentication?
    ): ResponseEntity<Any> {

        val landlordId = requireUser(auth)

        if (amount <= BigDecimal.ZERO) {
            return ResponseEntity.badRequest().body("Invalid amount")
        }

        if (amount < BigDecimal("3")) {
            return ResponseEntity.badRequest().body("Minimum withdrawal is KES 3")
        }

        val property = propertyRepository.findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        if (property.landlord.id != landlordId) {
            throw RuntimeException("Unauthorized")
        }

        val wallet = walletRepository.findByPropertyId(propertyId)
            ?: throw RuntimeException("Wallet not found")

        if (wallet.accountNumber.isNullOrBlank() && wallet.mpesaPhone.isNullOrBlank()) {
            return ResponseEntity.badRequest().body("Complete payout setup first")
        }

        payoutService.requestPayout(
            landlordId = landlordId,
            propertyId = propertyId,
            amount = amount
        )

        log.info("💸 Payout requested → landlord=$landlordId property=$propertyId amount=$amount")

        return ResponseEntity.ok(mapOf("message" to "Payout requested"))
    }

    // =====================================================
    // 🔥 ADMIN MARK AS PAID
    // =====================================================
    @PostMapping("/{id}/mark-paid")
    fun markPaid(
        @PathVariable id: UUID,
        @RequestParam nationalId: String,
        auth: Authentication?
    ): ResponseEntity<Any> {

        val adminId = requireAdmin(auth)

        if (nationalId.isBlank()) {
            return ResponseEntity.badRequest().body("National ID required")
        }

        payoutService.markAsPaid(
            payoutId = id,
            adminId = adminId,
            nationalId = nationalId
        )

        log.info("✅ Admin marked payout as PAID → payout=$id admin=$adminId")

        return ResponseEntity.ok(mapOf("message" to "Marked as paid"))
    }

    // =====================================================
    // ❌ ADMIN REJECT
    // =====================================================
    @PostMapping("/{id}/reject")
    fun rejectPayout(
        @PathVariable id: UUID,
        auth: Authentication?
    ): ResponseEntity<Any> {

        val adminId = requireAdmin(auth)

        payoutService.rejectPayout(
            payoutId = id,
            adminId = adminId
        )

        log.info("❌ Admin rejected payout → payout=$id admin=$adminId")

        return ResponseEntity.ok(mapOf("message" to "Payout rejected"))
    }
}