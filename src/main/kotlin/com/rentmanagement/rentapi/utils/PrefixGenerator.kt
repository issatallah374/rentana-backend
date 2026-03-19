package com.rentmanagement.rentapi.util

import com.rentmanagement.rentapi.repository.PropertyRepository
import org.springframework.stereotype.Component

@Component
class PrefixGenerator(
    private val propertyRepository: PropertyRepository
) {

    fun generatePrefix(propertyName: String): String {

        val base = propertyName
            .trim()
            .split(" ")
            .filter { it.isNotBlank() }
            .map { it.first().uppercaseChar() }
            .joinToString("")
            .take(2) // 🔥 LIMIT TO 2 LETTERS → MA instead of MAK
            .ifBlank { "PR" }

        var prefix = base
        var counter = 1

        while (propertyRepository.existsByAccountPrefix(prefix)) {
            prefix = "$base$counter"
            counter++
        }

        return prefix
    }
}