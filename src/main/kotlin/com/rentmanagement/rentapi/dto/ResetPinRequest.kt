package com.rentmanagement.rentapi.dto

import java.util.UUID

data class ResetPinRequest(
    val propertyId: UUID,
    val nationalId: String, // ✅ ADD THIS
    val otp: String,
    val newPin: String
)