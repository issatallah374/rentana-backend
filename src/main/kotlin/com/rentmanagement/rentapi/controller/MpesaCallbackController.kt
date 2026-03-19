package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.StkPushRequest
import com.rentmanagement.rentapi.services.MpesaService
import org.slf4j.LoggerFactory
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

@RestController
class MpesaCallbackController(
    private val mpesaService: MpesaService
) {

    private val log = LoggerFactory.getLogger(MpesaCallbackController::class.java)

    // =====================================================
    // 🔥 STK PUSH (APP INITIATED)
    // =====================================================
    @PostMapping("/api/mpesa/stk")
    fun triggerStk(
        @RequestBody request: StkPushRequest
    ): ResponseEntity<Map<String, String>> {

        mpesaService.initiateStkPush(
            request.phone,
            request.amount,
            request.landlordId
        )

        return ResponseEntity.ok(mapOf("message" to "STK push sent"))
    }

    // =====================================================
    // 🔵 STK CALLBACK
    // =====================================================
    @PostMapping("/api/mpesa/payment-callback")
    fun paymentCallback(
        @RequestBody payload: Map<String, Any>
    ): ResponseEntity<Map<String, String>> {

        log.info("🔥 STK CALLBACK RECEIVED → $payload")

        mpesaService.processPaymentCallback(payload)

        return ResponseEntity.ok(
            mapOf("ResultCode" to "0", "ResultDesc" to "Accepted")
        )
    }

    // =====================================================
    // 🟢 C2B VALIDATION (PAYBILL)
    // =====================================================
    @PostMapping("/api/c2b/validation")
    fun c2bValidation(
        @RequestBody payload: Map<String, Any>
    ): ResponseEntity<Map<String, String>> {

        log.info("🟢 C2B VALIDATION → $payload")

        return ResponseEntity.ok(
            mapOf("ResultCode" to "0", "ResultDesc" to "Accepted")
        )
    }

    // =====================================================
    // 🟢 C2B CONFIRMATION (🔥 REAL MONEY)
    // =====================================================
    @PostMapping("/api/c2b/confirmation")
    fun c2bConfirmation(
        @RequestBody payload: Map<String, Any>
    ): ResponseEntity<Map<String, String>> {

        log.info("💰 C2B CONFIRMATION RECEIVED → $payload")

        mpesaService.processC2BPayment(payload)

        return ResponseEntity.ok(
            mapOf("ResultCode" to "0", "ResultDesc" to "Accepted")
        )
    }

    // =====================================================
    // 🟢 SUBSCRIPTION CALLBACK
    // =====================================================
    @PostMapping("/api/mpesa/subscription-callback")
    fun subscriptionCallback(
        @RequestBody payload: Map<String, Any>
    ): ResponseEntity<Map<String, String>> {

        log.info("🟢 SUBSCRIPTION CALLBACK → $payload")

        mpesaService.processSubscriptionCallback(payload)

        return ResponseEntity.ok(
            mapOf("ResultCode" to "0", "ResultDesc" to "Accepted")
        )
    }
}