package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.PaymentResponse
import com.rentmanagement.rentapi.repository.PaymentRepository
import org.springframework.web.bind.annotation.*
import java.util.UUID

@RestController
@RequestMapping("/api/payments")
class PaymentController(
    private val paymentRepository: PaymentRepository
) {

    // ✅ EXISTING (keep if needed elsewhere)
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

    // ✅ NEW — Payments by Property
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
}