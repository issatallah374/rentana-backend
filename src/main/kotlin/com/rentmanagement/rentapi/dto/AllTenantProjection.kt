package com.rentmanagement.rentapi.dto

import java.time.LocalDate
import java.util.UUID

interface AllTenantProjection {

    val tenancyId: UUID
    val tenantName: String

    // ✅ nullable (DB can return null)
    val tenantPhone: String?

    val unitNumber: String
    val startDate: LocalDate

    // ✅ MUST match query alias: active
    val active: Boolean

    val balance: Double

    // ✅ financial status (OWING, PAID_EXTRA, CLEARED)
    val status: String?
}