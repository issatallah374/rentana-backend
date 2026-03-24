package com.rentmanagement.rentapi.dto

import java.time.LocalDate
import java.util.UUID

interface AllTenantProjection {

    val tenancyId: UUID
    val tenantName: String
    val tenantPhone: String
    val unitNumber: String
    val startDate: LocalDate
    val isActive: Boolean
    val balance: Double

    val status: String?   // ✅ nullable safety improvement

}