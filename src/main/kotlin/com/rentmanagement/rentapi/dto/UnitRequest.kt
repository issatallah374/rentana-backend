package com.rentmanagement.rentapi.dto

import java.math.BigDecimal

data class UnitRequest(
    val unitNumber: String,
    val rentAmount: BigDecimal,
    val propertyId: String
)