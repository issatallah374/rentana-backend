package com.rentmanagement.rentapi.dto

data class StkPushRequest(
    val phone: String,
    val amount: Double,
    val landlordId: String
)