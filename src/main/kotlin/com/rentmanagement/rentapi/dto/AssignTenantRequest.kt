package com.rentmanagement.rentapi.dto


import java.time.LocalDate

data class AssignTenantRequest(
    val fullName: String,
    val phoneNumber: String,
    val startDate: LocalDate
)