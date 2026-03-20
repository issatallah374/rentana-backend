package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.models.SubscriptionPlan
import com.rentmanagement.rentapi.repository.SubscriptionPlanRepository
import com.rentmanagement.rentapi.repository.SubscriptionRepository
import com.rentmanagement.rentapi.security.JwtUtil
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/subscriptions")
class SubscriptionController(
    private val subscriptionRepository: SubscriptionRepository,
    private val subscriptionPlanRepository: SubscriptionPlanRepository,
    private val jwtUtil: JwtUtil
) {

    // =========================================
    // 🔐 GET CURRENT USER SUBSCRIPTION
    // =========================================
    @GetMapping("/me")
    fun getMySubscription(
        @RequestHeader("Authorization") token: String
    ): ResponseEntity<Any> {

        val userId = jwtUtil.extractUserId(token.replace("Bearer ", ""))

        val subscription = subscriptionRepository
            .findTopByLandlordIdOrderByCreatedAtDesc(userId)

        if (subscription == null) {
            return ResponseEntity.ok(mapOf("status" to "NONE"))
        }

        return ResponseEntity.ok(
            mapOf(
                "status" to subscription.status,
                "planId" to subscription.planId,
                "startDate" to subscription.startDate,
                "endDate" to subscription.endDate
            )
        )
    }

    // =========================================
    // 📦 GET ALL PLANS
    // =========================================
    @GetMapping("/plans")
    fun getPlans(): List<SubscriptionPlan> {
        return subscriptionPlanRepository.findAll()
    }
}