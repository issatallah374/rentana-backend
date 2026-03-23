package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.StkPushRequest
import com.rentmanagement.rentapi.services.MpesaService
import org.slf4j.LoggerFactory
import org.springframework.http.ResponseEntity
import org.springframework.beans.factory.annotation.Value
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

        // ✅ STRICT VALIDATION (NO AMOUNT TRUST)
        if (
            request.phone.isBlank() ||
            request.landlordId.isBlank() ||
            request.planId.isBlank()
        ) {
            return ResponseEntity.badRequest().body(
                mapOf("error" to "Invalid request data")
            )
        }

        log.info(
            "📲 STK REQUEST → phone=${request.phone}, landlord=${request.landlordId}, plan=${request.planId}"
        )

        return try {

            mpesaService.initiateStkPush(
                phone = request.phone,
                landlordId = request.landlordId,
                planId = request.planId
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

    @Value("\${mpesa.callbackUrl}")
    lateinit var callbackUrl: String

    // =====================================================
    // 🔵 STK CALLBACK (SUBSCRIPTION ONLY)
    // =====================================================
    @PostMapping("/stk-callback", consumes = ["application/json"])
    fun stkCallbackPost(
        @RequestBody(required = false) payload: Map<String, Any>?
    ): ResponseEntity<Map<String, String>> {

        log.info("🔥 STK CALLBACK (POST) RECEIVED")

        if (payload == null) {
            log.warn("⚠️ Empty POST callback payload")
        } else {
            log.info("📦 CALLBACK PAYLOAD → {}", payload)

            try {
                mpesaService.processSubscriptionCallback(payload)
            } catch (e: Exception) {
                log.error("❌ STK CALLBACK PROCESSING FAILED", e)
            }
        }

        // ✅ ALWAYS ACKNOWLEDGE SAFARICOM
        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Accepted"
            )
        )
    }

    // =====================================================
    // 🧪 STK CALLBACK GET (PING / TEST)
    // =====================================================
    // =====================================================
// 🧪 STK CALLBACK GET (PING / TEST)
// =====================================================
    @GetMapping("/stk-callback")
    fun stkCallbackGet(): ResponseEntity<Map<String, String>> {

        log.info("🌐 STK CALLBACK (GET PING) RECEIVED")

        // 🔥 DEBUG ACTUAL VALUE FROM ENV
        log.error("🔥 CALLBACK URL USED → '$callbackUrl'")

        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Alive"
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

        log.info("🟢 C2B VALIDATION RECEIVED → {}", payload)

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
                log.info("💰 C2B CONFIRMATION RECEIVED → {}", payload)
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

    // =====================================================
// 🟡 SAFARICOM CALLBACK (CURRENT URL)
// =====================================================
    @PostMapping("/subscription-callback", consumes = ["application/json"])
    fun subscriptionCallback(
        @RequestBody(required = false) payload: Map<String, Any>?
    ): ResponseEntity<Map<String, String>> {

        log.warn("⚠️ CALLBACK HIT → /subscription-callback")

        if (payload == null) {
            log.warn("⚠️ Empty callback payload")
        } else {
            log.info("📦 CALLBACK PAYLOAD → {}", payload)

            try {
                mpesaService.processSubscriptionCallback(payload)
            } catch (e: Exception) {
                log.error("❌ CALLBACK PROCESSING FAILED", e)
            }
        }

        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Accepted"
            )
        )
    }
    @GetMapping("/subscription-callback")
    fun subscriptionCallbackGet(): ResponseEntity<Map<String, String>> {

        log.warn("🌐 SAFARICOM PING → /subscription-callback")

        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Alive"
            )
        )
    }

}