package com.rentmanagement.rentapi.dto

import java.math.BigDecimal
import java.util.UUID

data class RequestPayoutWithPin(
    val propertyId: UUID,
    val amount: BigDecimal,
    val pin: String
)