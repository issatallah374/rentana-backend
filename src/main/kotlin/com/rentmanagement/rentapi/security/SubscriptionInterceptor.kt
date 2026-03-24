package com.rentmanagement.rentapi.security

import com.rentmanagement.rentapi.repository.SubscriptionRepository
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Component
import org.springframework.web.servlet.HandlerInterceptor
import java.time.LocalDateTime

@Component
class SubscriptionInterceptor(
    private val subscriptionRepository: SubscriptionRepository,
    private val jwtUtil: JwtUtil
) : HandlerInterceptor {

    private val log = LoggerFactory.getLogger(SubscriptionInterceptor::class.java)

    override fun preHandle(
        request: HttpServletRequest,
        response: HttpServletResponse,
        handler: Any
    ): Boolean {

        val path = request.requestURI

        // =====================================================
        // ✅ PUBLIC / SAFE ENDPOINTS
        // =====================================================
        if (
            path.startsWith("/api/auth") ||
            path.startsWith("/api/mpesa") ||       // MPESA callbacks
            path.startsWith("/api/subscriptions") ||
            path.startsWith("/error")
        ) {
            return true
        }

        val authHeader = request.getHeader("Authorization")

        // =====================================================
        // ✅ NO TOKEN → LET SPRING SECURITY HANDLE
        // =====================================================
        if (authHeader.isNullOrBlank() || !authHeader.startsWith("Bearer ")) {
            return true
        }

        val token = authHeader.substring(7)

        try {

            val userId = jwtUtil.extractUserId(token)
            val role = jwtUtil.extractRole(token) // 🔥 REQUIRED

            // =====================================================
            // ✅ ADMIN BYPASS (CRITICAL FIX)
            // =====================================================
            if (role == "ADMIN") {
                return true
            }

            // =====================================================
            // ✅ ADMIN ROUTES BYPASS (EXTRA SAFETY)
            // =====================================================
            if (path.startsWith("/admin")) {
                return true
            }

            // =====================================================
            // 🔍 CHECK SUBSCRIPTION (LANDLORD ONLY)
            // =====================================================
            val sub = subscriptionRepository
                .findTopByLandlordIdOrderByCreatedAtDesc(userId)

            val isExpired =
                sub == null ||
                        sub.status != "ACTIVE" ||
                        sub.endDate?.isBefore(LocalDateTime.now()) != false

            // =====================================================
            // ❌ BLOCK IF NO ACTIVE SUBSCRIPTION
            // =====================================================
            if (isExpired) {

                log.warn("❌ Subscription required → user=$userId path=$path")

                // ✅ allow wallet access even if expired
                if (path.contains("/wallet")) {
                    return true
                }

                response.status = 403
                response.contentType = "application/json"
                response.writer.write("""{"error":"SUBSCRIPTION_REQUIRED"}""")

                return false
            }

            return true

        } catch (e: Exception) {

            log.error("❌ Subscription check failed", e)

            // 🚫 NEVER BLOCK on unexpected errors
            return true
        }
    }
}