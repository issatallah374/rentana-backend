package com.rentmanagement.rentapi.dto

import java.util.UUID        // ✅ ADD
import java.time.LocalDate   // ✅ ADD
import java.math.BigDecimal  // already added

data class TenancyRequest(

    val tenantId: UUID,

    val unitId: UUID,

    val rentAmount: BigDecimal,

    val startDate: LocalDate

)
