package com.rentmanagement.rentapi.dto

data class PinLoginRequest(
    val phone: String,
    val pin: String
)