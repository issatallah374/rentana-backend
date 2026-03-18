package com.rentmanagement.rentapi.dto

import java.math.BigDecimal
import java.util.UUID

interface ActiveTenantProjection {

    fun getTenancyId(): UUID
    fun getUnitId(): UUID
    fun getUnitNumber(): String
    fun getTenantName(): String
    fun getBalance(): BigDecimal
    fun getStatus(): String?   // ✅ nullable safety improvement
}
