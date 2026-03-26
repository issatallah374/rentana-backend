package com.rentmanagement.rentapi.dto

data class SetUserPinRequest(
    val phone: String,
    val otp: String,
    val pin: String
)