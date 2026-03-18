package com.rentmanagement.rentapi.dto

import java.time.LocalDateTime
import java.util.UUID

data class PropertyResponse(
    val id: UUID,
    val name: String,
    val address: String,
    val city: String,
    val country: String,
    val createdAt: LocalDateTime
)
