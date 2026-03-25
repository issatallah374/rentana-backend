package com.rentmanagement.rentapi.dto

import java.util.UUID

data class ForgotPinRequest(
    val propertyId: UUID,
    val nationalId: String
)