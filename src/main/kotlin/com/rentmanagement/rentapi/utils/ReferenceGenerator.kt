package com.rentmanagement.rentapi.utils

object ReferenceGenerator {

    fun generatePropertyPrefix(propertyName: String): String {
        return propertyName
            .trim()
            .split(" ")
            .filter { it.isNotBlank() }
            .take(2)
            .map { it.first().uppercaseChar() }
            .joinToString("")
            .ifBlank { "PR" }
    }

    fun generateUnitReference(prefix: String, unitNumber: String): String {

        val digits = unitNumber.filter { it.isDigit() }

        val safeNumber = if (digits.isBlank()) "001" else digits.padStart(3, '0')

        return "$prefix$safeNumber"
    }
}