package com.rentmanagement.rentapi.repository

import java.util.UUID

interface PropertySummaryProjection {

    val propertyId: UUID
    val totalUnits: Long
    val activeTenancies: Long
    val totalExpected: Double
    val totalCollected: Double
}