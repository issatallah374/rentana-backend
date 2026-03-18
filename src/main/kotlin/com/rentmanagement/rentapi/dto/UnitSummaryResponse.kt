package com.rentmanagement.rentapi.dto

import java.math.BigDecimal
import java.util.UUID

data class UnitSummaryResponse(
    val id: UUID,
    val unitNumber: String,
    val rentAmount: BigDecimal,
    val accountNumber: String,
    val tenantName: String?,
    val isOccupied: Boolean
)


