package com.rentmanagement.rentapi.dto

data class PropertySummaryResponse(

    val propertyId: String,

    val unitCount: Int,

    val activeTenancies: Int,

    // 💰 RENT EXPECTED THIS MONTH
    val totalExpected: Double,

    // 💵 RENT COLLECTED THIS MONTH
    val totalCollected: Double,

    // ⚠️ CURRENT MONTH DEFICIT
    val arrears: Double,

    // ✅ COLLECTION RATE %
    val collectionRate: Double,

    // 👥 PAID TENANTS
    val paidTenants: Int,

    // ❌ UNPAID TENANTS
    val unpaidTenants: Int
)