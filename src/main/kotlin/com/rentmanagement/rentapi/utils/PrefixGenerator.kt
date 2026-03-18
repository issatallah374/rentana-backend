package com.rentmanagement.rentapi.util

import com.rentmanagement.rentapi.repository.PropertyRepository
import org.springframework.stereotype.Component
import java.util.Locale

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
            .take(3)
            .ifBlank { "PRP" }

        var prefix = base
        var counter = 1

        while (propertyRepository.existsByAccountPrefix(prefix)) {
            prefix = "$base$counter"
            counter++
        }

        return prefix
    }
}