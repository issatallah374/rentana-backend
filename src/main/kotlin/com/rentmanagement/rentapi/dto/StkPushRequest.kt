package com.rentmanagement.rentapi.dto

data class StkPushRequest(
    val phone: String,
    val landlordId: String,
    val planId: String
)