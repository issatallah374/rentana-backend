package com.rentmanagement.rentapi.dto

import java.math.BigDecimal
import java.util.UUID

interface ActiveTenantProjection {

    val tenancyId: UUID
    val unitId: UUID
    val unitNumber: String
    val tenantName: String
    val balance: BigDecimal

    // ✅ financial status (OWING, PAID_EXTRA, CLEARED)
    val status: String?

    // ✅ nullable for safety (can be null in DB)
    val tenantPhone: String?
}