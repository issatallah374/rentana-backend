package com.rentmanagement.rentapi.dto

data class RegisterRequest(
    val fullName: String,
    val email: String,
    val phone: String,
    val password: String,
    val role: String = "LANDLORD"
)