package com.rentmanagement.rentapi.mapper

import com.rentmanagement.rentapi.dto.TenancyResponse
import com.rentmanagement.rentapi.models.Tenancy

object TenancyMapper {

    fun toResponse(tenancy: Tenancy): TenancyResponse {

        return TenancyResponse(
            id = tenancy.id!!,
            unitId = tenancy.unit.id!!,
            tenantId = tenancy.tenant.id!!,
            rentAmount = tenancy.rentAmount.toDouble(),
            startDate = tenancy.startDate,
            isActive = tenancy.isActive


        )
    }
}
