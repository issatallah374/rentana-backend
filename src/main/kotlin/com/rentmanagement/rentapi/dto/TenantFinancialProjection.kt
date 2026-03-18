package com.rentmanagement.rentapi.dto

import java.time.LocalDate
import java.util.UUID

interface TenantFinancialProjection {

    val tenancyId: UUID
    val tenantName: String
    val unitNumber: String
    val rentAmount: Double
    val startDate: LocalDate

    val totalPaid: Double
    val totalCharged: Double
    val balance: Double
}