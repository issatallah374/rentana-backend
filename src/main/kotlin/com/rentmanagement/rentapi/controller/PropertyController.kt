package com.rentmanagement.rentapi.controllers

import com.rentmanagement.rentapi.models.Property
import com.rentmanagement.rentapi.models.PropertyRequest
import com.rentmanagement.rentapi.repository.*
import com.rentmanagement.rentapi.util.PrefixGenerator
import com.rentmanagement.rentapi.dto.PropertySummaryResponse
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.http.ResponseEntity
import org.springframework.http.HttpStatus
import org.springframework.web.server.ResponseStatusException
import java.util.UUID

@RestController
@RequestMapping("/api/properties")
class PropertyController(
    private val propertyRepository: PropertyRepository,
    private val userRepository: UserRepository,
    private val prefixGenerator: PrefixGenerator,
    private val jdbcTemplate: JdbcTemplate,

    // 🔥 ADD THESE
    private val subscriptionRepository: SubscriptionRepository,
    private val subscriptionPlanRepository: SubscriptionPlanRepository
) {

    // ==============================
    // GET ALL PROPERTIES
    // ==============================
    @GetMapping
    fun getProperties(authentication: Authentication): ResponseEntity<List<Property>> {

        val userId = UUID.fromString(authentication.name)

        val user = userRepository.findById(userId)
            .orElseThrow { RuntimeException("User not found") }

        val properties = propertyRepository.findByLandlord(user)

        return ResponseEntity.ok(properties)
    }


    // ==============================
    // CREATE PROPERTY (🔥 PROTECTED)
    // ==============================
    @PostMapping
    fun createProperty(
        @RequestBody request: PropertyRequest,
        authentication: Authentication
    ): ResponseEntity<Property> {

        val userId = UUID.fromString(authentication.name)

        val user = userRepository.findById(userId)
            .orElseThrow { RuntimeException("User not found") }

        // =====================================
        // 🔒 CHECK ACTIVE SUBSCRIPTION
        // =====================================
        val subscription = subscriptionRepository
            .findTopByLandlordIdOrderByCreatedAtDesc(userId)

        if (subscription == null || subscription.status != "ACTIVE") {
            throw ResponseStatusException(
                HttpStatus.FORBIDDEN,
                "❌ Active subscription required"
            )
        }

        // =====================================
        // 🏢 CHECK PROPERTY LIMIT
        // =====================================
        val plan = subscriptionPlanRepository.findById(subscription.planId)
            .orElseThrow {
                ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Plan not found")
            }

        val propertyCount = propertyRepository.countByLandlord(user)

        if (propertyCount >= plan.propertyLimit) {
            throw ResponseStatusException(
                HttpStatus.FORBIDDEN,
                "❌ Property limit reached (${plan.propertyLimit})"
            )
        }

        // =====================================
        // ✅ CREATE PROPERTY
        // =====================================
        val prefix = prefixGenerator.generatePrefix(request.name)

        val property = Property(
            name = request.name,
            address = request.address,
            city = request.city,
            country = request.country,
            accountPrefix = prefix,
            landlord = user
        )

        val saved = propertyRepository.save(property)

        return ResponseEntity.ok(saved)
    }


    // ==============================
    // PROPERTY SUMMARY
    // ==============================
    @GetMapping("/{id}/summary")
    fun getPropertySummary(
        @PathVariable id: String,
        authentication: Authentication
    ): ResponseEntity<PropertySummaryResponse> {

        val propertyId = UUID.fromString(id)
        val userId = UUID.fromString(authentication.name)

        val property = propertyRepository.findById(propertyId)
            .orElseThrow { RuntimeException("Property not found") }

        // 🔒 Security check
        if (property.landlord.id != userId) {
            return ResponseEntity.status(403).build()
        }

        val result = jdbcTemplate.queryForList(
            """
            SELECT *
            FROM public.property_summary
            WHERE property_id = ?
            """.trimIndent(),
            propertyId
        )

        if (result.isEmpty()) {
            return ResponseEntity.ok(
                PropertySummaryResponse(
                    propertyId = id,
                    unitCount = 0,
                    activeTenancies = 0,
                    totalExpected = 0.0,
                    totalCollected = 0.0
                )
            )
        }

        val row = result[0]

        val response = PropertySummaryResponse(
            propertyId = row["property_id"].toString(),
            unitCount = (row["unit_count"] as? Number)?.toInt() ?: 0,
            activeTenancies = (row["active_tenancies"] as? Number)?.toInt() ?: 0,
            totalExpected = (row["total_expected"] as? Number)?.toDouble() ?: 0.0,
            totalCollected = (row["total_collected"] as? Number)?.toDouble() ?: 0.0
        )

        return ResponseEntity.ok(response)
    }
}