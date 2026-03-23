package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.services.MpesaService
import org.slf4j.LoggerFactory
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

@RestController
class C2BController(
    private val mpesaService: MpesaService
) {

    private val log = LoggerFactory.getLogger(C2BController::class.java)

    // =====================================================
    // 🟢 VALIDATION (NEW + LEGACY)
    // =====================================================
    @PostMapping(
        value = [
            "/api/payments/c2b/validation", // ✅ NEW (SAFE)
            "/api/c2b/validation"           // ⚠️ LEGACY (SAFARICOM)
        ],
        consumes = ["application/json"]
    )
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
    // 💰 CONFIRMATION (NEW + LEGACY)
    // =====================================================
    @PostMapping(
        value = [
            "/api/payments/c2b/confirmation", // ✅ NEW
            "/api/c2b/confirmation"           // ⚠️ LEGACY
        ],
        consumes = ["application/json"]
    )
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
}