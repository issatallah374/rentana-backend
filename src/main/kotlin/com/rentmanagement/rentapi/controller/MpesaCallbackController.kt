package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.services.MpesaService
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/mpesa")
class MpesaCallbackController(
    private val mpesaService: MpesaService
) {

    // =========================
    // RENT PAYMENTS (TENANTS)
    // =========================
    @PostMapping("/payment-callback")
    fun paymentCallback(
        @RequestBody payload: Map<String, Any>
    ): ResponseEntity<Map<String, String>> {

        mpesaService.processPaymentCallback(payload)

        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Accepted"
            )
        )
    }

    // =========================
    // SUBSCRIPTIONS (YOU 💰)
    // =========================
    @PostMapping("/subscription-callback")
    fun subscriptionCallback(
        @RequestBody payload: Map<String, Any>
    ): ResponseEntity<Map<String, String>> {

        mpesaService.processSubscriptionCallback(payload)

        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Accepted"
            )
        )
    }
}