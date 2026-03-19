package com.rentmanagement.rentapi.utils

object ReferenceGenerator {

    fun generateUnitReference(prefix: String, unitNumber: String): String {

        // 🔥 Remove everything except digits
        val digits = unitNumber.filter { it.isDigit() }

        // 🔥 No padding → 3 stays 3 (not 003)
        val safeNumber = if (digits.isBlank()) "1" else digits

        // 🔥 Normalize prefix (extra safety)
        val cleanPrefix = prefix
            .uppercase()
            .replace("\\s".toRegex(), "")
            .replace("-", "")

        // ✅ FINAL RESULT → MA3
        return "$cleanPrefix$safeNumber"
    }
}