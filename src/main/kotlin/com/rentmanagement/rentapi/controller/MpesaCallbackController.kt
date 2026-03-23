package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.StkPushRequest
import com.rentmanagement.rentapi.services.MpesaService
import org.slf4j.LoggerFactory
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/mpesa")
class MpesaCallbackController(
    private val mpesaService: MpesaService
) {

    private val log = LoggerFactory.getLogger(MpesaCallbackController::class.java)

    // =====================================================
    // 🔥 STK PUSH (SUBSCRIPTION ONLY)
    // =====================================================
    @PostMapping("/stk", consumes = ["application/json"])
    fun triggerStk(
        @RequestBody request: StkPushRequest
    ): ResponseEntity<Map<String, String>> {

        if (request.phone.isBlank() || request.landlordId.isBlank() || request.amount <= 0) {
            return ResponseEntity.badRequest().body(
                mapOf("error" to "Invalid request data")
            )
        }

        log.info(
            "📲 STK REQUEST → phone=${request.phone}, amount=${request.amount}, landlord=${request.landlordId}"
        )

        return try {

            mpesaService.initiateStkPush(
                request.phone,
                request.amount,
                request.landlordId
            )

            ResponseEntity.ok(
                mapOf("message" to "STK push sent successfully")
            )

        } catch (e: Exception) {

            log.error("❌ STK TRIGGER FAILED", e)

            ResponseEntity.internalServerError().body(
                mapOf("error" to "Failed to initiate STK push")
            )
        }
    }

    // =====================================================
    // 🔵 STK CALLBACK (SUBSCRIPTION ONLY)
    // =====================================================
    @PostMapping("/stk-callback", consumes = ["application/json"])
    fun stkCallback(
        @RequestBody payload: Map<String, Any>?
    ): ResponseEntity<Map<String, String>> {

        log.info("🔥🔥🔥 STK CALLBACK RECEIVED 🔥🔥🔥")

        if (payload == null) {
            log.warn("⚠️ Empty STK callback received")

            return ResponseEntity.ok(
                mapOf(
                    "ResultCode" to "0",
                    "ResultDesc" to "Accepted"
                )
            )
        }

        log.info("📦 FULL CALLBACK PAYLOAD → {}", payload)

        try {
            // ✅ Just pass everything to service
            mpesaService.processSubscriptionCallback(payload)

        } catch (e: Exception) {
            log.error("❌ STK CALLBACK PROCESSING FAILED", e)
            // still return success to avoid retries
        }

        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Accepted"
            )
        )
    }

    // =====================================================
    // 🟢 C2B VALIDATION (PAYBILL - RENT)
    // =====================================================
    @PostMapping("/c2b/validation", consumes = ["application/json"])
    fun c2bValidation(
        @RequestBody payload: Map<String, Any>?
    ): ResponseEntity<Map<String, String>> {

        log.info("🟢 C2B VALIDATION RECEIVED")

        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Accepted"
            )
        )
    }

    // =====================================================
    // 💰 C2B CONFIRMATION (RENT PAYMENTS)
    // =====================================================
    @PostMapping("/c2b/confirmation", consumes = ["application/json"])
    fun c2bConfirmation(
        @RequestBody payload: Map<String, Any>?
    ): ResponseEntity<Map<String, String>> {

        try {

            if (payload == null) {
                log.warn("⚠️ Empty C2B confirmation")
            } else {
                log.info("💰 C2B CONFIRMATION RECEIVED")
                mpesaService.processC2BPayment(payload)
            }

        } catch (e: Exception) {
            log.error("❌ C2B PROCESSING FAILED", e)
        }

        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Accepted"
            )
        )
    }
}