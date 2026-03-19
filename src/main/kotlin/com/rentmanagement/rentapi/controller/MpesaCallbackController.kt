package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.StkPushRequest
import com.rentmanagement.rentapi.services.MpesaService
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/mpesa")
class MpesaCallbackController(
    private val mpesaService: MpesaService
) {

    // =====================================================
    // 🔥 STK PUSH
    // =====================================================
    @PostMapping("/stk")
    fun triggerStk(
        @RequestBody request: StkPushRequest
    ): ResponseEntity<Map<String, String>> {

        mpesaService.initiateStkPush(
            request.phone,
            request.amount,
            request.landlordId
        )

        return ResponseEntity.ok(
            mapOf("message" to "STK push sent")
        )
    }

    // =====================================================
    // 🔵 RENT PAYMENTS CALLBACK
    // =====================================================
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

    // =====================================================
    // 🟢 SUBSCRIPTION CALLBACK
    // =====================================================
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