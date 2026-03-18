package com.rentmanagement.rentapi.dto

import java.math.BigDecimal
import java.time.LocalDateTime
import java.util.UUID

data class PaymentResponse(
    val id: UUID,
    val amount: BigDecimal,
    val paymentMethod: String,
    val transactionCode: String?,
    val receiptNumber: String?,
    val paymentDate: LocalDateTime
)