package com.rentmanagement.rentapi.dto

data class ResetPinRequest(
    val nationalId: String,
    val otp: String,
    val newPin: String
)