package com.rentmanagement.rentapi.controllers

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
    private val payoutService: PayoutService
) {

    private val log = LoggerFactory.getLogger(PayoutController::class.java)

    // =====================================================
    // 💸 REQUEST PAYOUT (CLEAN + SECURE)
    // =====================================================
    @PostMapping("/request")
    fun requestPayout(
        @RequestParam propertyId: UUID,
        @RequestParam amount: BigDecimal,
        authentication: Authentication?
    ): ResponseEntity<String> {

        if (authentication == null || authentication.name.isNullOrBlank()) {
            log.error("❌ Unauthorized payout attempt")
            throw RuntimeException("Unauthorized")
        }

        val landlordId = try {
            UUID.fromString(authentication.name)
        } catch (e: Exception) {
            log.error("❌ Invalid landlordId in token: ${authentication.name}")
            throw RuntimeException("Invalid user identity")
        }

        log.info("💸 Authenticated payout request → landlord=$landlordId")

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

        if (authentication == null) {
            throw RuntimeException("Unauthorized")
        }

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

        if (authentication == null) {
            throw RuntimeException("Unauthorized")
        }

        val roles = authentication.authorities.map { it.authority }

        if (!roles.contains("ROLE_ADMIN")) {
            throw RuntimeException("Forbidden")
        }

        payoutService.rejectPayout(id)

        return ResponseEntity.ok("Payout rejected")
    }
}