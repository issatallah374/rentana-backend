package com.rentmanagement.rentapi.controllers

import com.rentmanagement.rentapi.services.PayoutService
import org.springframework.http.ResponseEntity
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import java.math.BigDecimal
import java.util.UUID

@RestController
@RequestMapping("/api/payouts")
class PayoutController(
    private val payoutService: PayoutService
) {

    // =====================================================
    // 🔥 REQUEST PAYOUT (SECURE)
    // =====================================================
    @PostMapping("/request")
    fun requestPayout(
        @RequestParam propertyId: UUID,
        @RequestParam amount: BigDecimal,
        @RequestParam method: String,
        @RequestParam destination: String,
        authentication: Authentication
    ): ResponseEntity<String> {

        val landlordId = UUID.fromString(authentication.name)

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
        @PathVariable id: UUID
    ): ResponseEntity<String> {

        payoutService.markAsPaid(id)

        return ResponseEntity.ok("Marked as paid")
    }
}