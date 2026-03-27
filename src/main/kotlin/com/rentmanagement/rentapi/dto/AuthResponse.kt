package com.rentmanagement.rentapi.dto

data class AuthResponse(
    val token: String,
    val phone: String   // ✅ ADD THIS

)
