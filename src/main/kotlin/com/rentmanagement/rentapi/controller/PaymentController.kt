package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.PaymentResponse
import com.rentmanagement.rentapi.repository.PaymentRepository
import com.rentmanagement.rentapi.repository.SubscriptionPlanRepository
import com.rentmanagement.rentapi.services.MpesaStkService
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*
import java.util.UUID

@RestController
@RequestMapping("/api/payments")
class PaymentController(
    private val paymentRepository: PaymentRepository,
    private val mpesaStkService: MpesaStkService,
    private val subscriptionPlanRepository: SubscriptionPlanRepository
) {

    // =========================
    // 📄 TENANCY PAYMENTS
    // =========================
    @GetMapping("/tenancy/{tenancyId}")
    fun getPaymentsByTenancy(
        @PathVariable tenancyId: String
    ): List<PaymentResponse> {

        return paymentRepository
            .findByTenancy_IdOrderByPaymentDateDesc(UUID.fromString(tenancyId))
            .map {
                PaymentResponse(
                    id = it.id!!,
                    amount = it.amount,
                    paymentMethod = it.paymentMethod,
                    transactionCode = it.transactionCode,
                    receiptNumber = it.receiptNumber,
                    paymentDate = it.paymentDate
                )
            }
    }

    // =========================
    // 🏢 PROPERTY PAYMENTS
    // =========================
    @GetMapping("/property/{propertyId}")
    fun getPaymentsByProperty(
        @PathVariable propertyId: String
    ): List<PaymentResponse> {

        return paymentRepository
            .findByPropertyId(UUID.fromString(propertyId))
            .map {
                PaymentResponse(
                    id = it.id!!,
                    amount = it.amount,
                    paymentMethod = it.paymentMethod,
                    transactionCode = it.transactionCode,
                    receiptNumber = it.receiptNumber,
                    paymentDate = it.paymentDate
                )
            }
    }

    // =========================
    // 💰 LANDLORD SUBSCRIPTION STK (🔥 FINAL CLEAN FLOW)
    // =========================
    @PostMapping("/stk/subscribe")
    fun initiateSubscriptionSTK(
        @RequestParam phone: String,
        @RequestParam landlordId: UUID,
        @RequestParam planId: UUID
    ): ResponseEntity<Any> {

        // ✅ VALIDATION
        if (phone.isBlank()) {
            return ResponseEntity.badRequest().body(mapOf("error" to "Phone is required"))
        }

        // ✅ FETCH PLAN (SOURCE OF TRUTH)
        val plan = subscriptionPlanRepository.findById(planId)
            .orElseThrow { RuntimeException("Plan not found") }

        // ✅ USE PLAN PRICE (NO GUESSING)
        val response = mpesaStkService.stkPush(
            phone = phone,
            amount = plan.price,
            landlordId = landlordId,
            planId = planId
        )

        return ResponseEntity.ok(response)
    }
}