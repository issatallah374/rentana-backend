package com.rentmanagement.rentapi.models

data class PropertyRequest(
    val name: String,
    val address: String,
    val city: String,
    val country: String,
)
