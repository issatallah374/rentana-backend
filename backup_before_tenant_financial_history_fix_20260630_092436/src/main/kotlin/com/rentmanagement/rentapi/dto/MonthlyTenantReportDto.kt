package com.rentmanagement.rentapi.dto

import java.math.BigDecimal
import java.util.UUID

data class MonthlyTenantReportDto(

    val tenancyId: UUID,

    val tenantName: String,

    val unitName: String,

    val propertyId: UUID,

    val month: Int,

    val year: Int,

    // Total rent charged for month
    val rentCharged: BigDecimal,

    // Total payments received for month
    val amountPaid: BigDecimal,

    // Remaining balance
    val balance: BigDecimal,

    // PAID / PARTIAL / UNPAID
    val status: String
)