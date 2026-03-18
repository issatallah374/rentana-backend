package com.rentmanagement.rentapi.dto

import java.time.LocalDateTime
import java.util.UUID

data class UserResponse(
    val id: UUID,
    val fullName: String,
    val email: String,
    val role: String,
    val isActive: Boolean,
    val createdAt: LocalDateTime
)
