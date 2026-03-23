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
    @GetMapping("/stk-callback")
    fun stkCallbackGet(): ResponseEntity<Map<String, String>> {

        log.info("🌐 STK CALLBACK (GET PING) RECEIVED")

        log.error("🔥 CALLBACK URL USED → '$callbackUrl'")

        return ResponseEntity.ok(
            mapOf(
                "ResultCode" to "0",
                "ResultDesc" to "Alive"
            )
        )
    }

    // =====================================================
    // 🟡 SAFARICOM CALLBACK (ALT ROUTE)
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