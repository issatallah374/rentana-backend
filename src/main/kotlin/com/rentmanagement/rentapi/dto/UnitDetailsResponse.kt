package com.rentmanagement.rentapi.dto

import java.math.BigDecimal
import java.util.UUID

data class UnitDetailsResponse(

    val id: UUID,

    val unitNumber: String,

    val rentAmount: BigDecimal,

    val accountNumber: String,

    val referenceNumber: String,

    val isActive: Boolean,

    val tenantName: String? = null,

    val tenantPhone: String? = null,

    val isOccupied: Boolean = false,

    // NEW FIELDS
    val tenancyId: UUID? = null,

    val tenancyActive: Boolean? = null
)