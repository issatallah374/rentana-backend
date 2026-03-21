package com.rentmanagement.rentapi.dto

data class PayoutSetupRequest(
    val bankName: String?,
    val accountNumber: String?,
    val mpesaPhone: String?
)