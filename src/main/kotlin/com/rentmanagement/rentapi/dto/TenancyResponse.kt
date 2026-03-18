package com.rentmanagement.rentapi.dto

import java.time.LocalDate
import java.util.UUID

data class TenancyResponse(
    val id: UUID,
    val unitId: UUID,
    val tenantId: UUID,
    val rentAmount: Double,
    val startDate: LocalDate,
    val isActive: Boolean


)
