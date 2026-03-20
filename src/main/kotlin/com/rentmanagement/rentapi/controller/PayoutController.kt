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
    // 🔥 REQUEST PAYOUT (SECURE)
    // =====================================================
    @PostMapping("/request")
    fun requestPayout(
        @RequestParam propertyId: UUID,
        @RequestParam amount: BigDecimal,
        @RequestParam method: String,
        @RequestParam destination: String,
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
            landlordId,
            propertyId,
            amount,
            method,
            destination
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
            log.error("❌ Unauthorized admin attempt")
            throw RuntimeException("Unauthorized")
        }

        // 🔒 OPTIONAL: enforce ADMIN role (recommended)
        val roles = authentication.authorities.map { it.authority }

        if (!roles.contains("ROLE_ADMIN")) {
            log.error("❌ Non-admin tried to mark payout as paid")
            throw RuntimeException("Forbidden")
        }

        log.info("💰 Admin processing payout → id=$id")

        payoutService.markAsPaid(id)

        return ResponseEntity.ok("Marked as paid")
    }

    // =====================================================
    // ❌ ADMIN REJECT PAYOUT
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