package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.Property
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.UserRepository
import org.springframework.stereotype.Service
import java.util.UUID
import kotlin.random.Random

@Service
class PropertyService(
    private val propertyRepository: PropertyRepository,
    private val userRepository: UserRepository
) {

    fun createProperty(property: Property): Property {

        // Generate prefix automatically if missing
        if (property.accountPrefix.isNullOrBlank()) {
            property.accountPrefix = generateUniquePrefix(property.name)
        }

        return propertyRepository.save(property)
    }

    private fun generateUniquePrefix(propertyName: String?): String {

        val base = propertyName
            ?.uppercase()
            ?.replace("[^A-Z]".toRegex(), "")
            ?.take(3)
            ?: "PRP"

        var prefix: String

        do {

            val randomNumber = Random.nextInt(100, 999)

            prefix = "$base$randomNumber"

        } while (propertyRepository.findByAccountPrefix(prefix) != null)

        return prefix
    }

    fun getPropertiesByLandlord(landlordId: UUID): List<Property> {

        val user = userRepository.findById(landlordId)
            .orElseThrow { RuntimeException("User not found") }

        return propertyRepository.findByLandlord(user)
    }

    fun getPropertyById(id: UUID): Property {

        return propertyRepository.findById(id)
            .orElseThrow { RuntimeException("Property not found") }
    }

    fun deleteProperty(id: UUID) {

        propertyRepository.deleteById(id)
    }
}