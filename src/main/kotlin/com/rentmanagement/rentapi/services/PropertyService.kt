package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.Property
import com.rentmanagement.rentapi.models.Wallet
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.SubscriptionPlanRepository
import com.rentmanagement.rentapi.repository.SubscriptionRepository
import com.rentmanagement.rentapi.repository.UserRepository
import com.rentmanagement.rentapi.repository.WalletRepository
import org.springframework.stereotype.Service
import java.time.LocalDateTime
import java.util.UUID
import kotlin.random.Random

@Service
class PropertyService(
    private val propertyRepository: PropertyRepository,
    private val userRepository: UserRepository,
    private val subscriptionRepository: SubscriptionRepository,
    private val subscriptionPlanRepository: SubscriptionPlanRepository,
    private val walletRepository: WalletRepository
) {

    fun createProperty(property: Property): Property {

        val landlordId = property.landlord.id
            ?: throw RuntimeException("Invalid landlord")

        val sub = subscriptionRepository
            .findTopByLandlordIdOrderByCreatedAtDesc(landlordId)
            ?: throw RuntimeException("No active subscription")

        // ✅ SAFE NULL HANDLING
        val isExpired =
            sub.status != "ACTIVE" ||
                    sub.endDate?.isBefore(LocalDateTime.now()) != false

        if (isExpired) {
            throw RuntimeException("Subscription expired")
        }

        // 🔥 FETCH PLAN USING planId (FIXED)
        val plan = subscriptionPlanRepository.findById(sub.planId)
            .orElseThrow { RuntimeException("Subscription plan not found") }

        val currentCount = propertyRepository.countByLandlordId(landlordId)
        val maxAllowed = plan.propertyLimit

        if (currentCount >= maxAllowed) {
            throw RuntimeException("PROPERTY_LIMIT_REACHED")
        }

        // ✅ Generate prefix
        if (property.accountPrefix.isNullOrBlank()) {
            property.accountPrefix = generateUniquePrefix(property.name)
        }

        // ✅ SAVE PROPERTY
        val savedProperty = propertyRepository.save(property)

        // 🔥 CREATE WALLET (NO landlord anymore)
        val wallet = Wallet(
            property = savedProperty
        )

        walletRepository.save(wallet)

        return savedProperty
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