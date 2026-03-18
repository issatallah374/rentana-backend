package com.rentmanagement.rentapi.dto

data class PropertySummaryResponse(
    val propertyId: String,
    val unitCount: Int,
    val activeTenancies: Int,
    val totalExpected: Double,
    val totalCollected: Double
)