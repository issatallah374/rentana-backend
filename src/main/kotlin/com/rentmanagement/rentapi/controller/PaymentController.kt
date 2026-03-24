package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.PaymentResponse
import com.rentmanagement.rentapi.repository.PaymentRepository
import com.rentmanagement.rentapi.repository.SubscriptionPlanRepository
import com.rentmanagement.rentapi.services.MpesaStkService
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*
import java.util.UUID
import java.security.Principal
import com.rentmanagement.rentapi.repository.PropertyRepository

@RestController
@RequestMapping("/api/payments")
class PaymentController(
    private val paymentRepository: PaymentRepository,
    private val mpesaStkService: MpesaStkService,
    private val subscriptionPlanRepository: SubscriptionPlanRepository,
    private val propertyRepository: PropertyRepository
){

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
        @PathVariable propertyId: String,
        principal: Principal
    ): List<PaymentResponse> {

        val userId = UUID.fromString(principal.name)

        val property = propertyRepository.findById(UUID.fromString(propertyId))
            .orElseThrow { RuntimeException("Property not found") }

        if (property.landlord.id != userId) {
            throw RuntimeException("Forbidden")
        }

        return paymentRepository
            .findByPropertyId(property.id!!)
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