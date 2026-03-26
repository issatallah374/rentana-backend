package com.rentmanagement.rentapi.dto

data class VerifyOtpRequest(
    val phone: String,
    val otp: String
)