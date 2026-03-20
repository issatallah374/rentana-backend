package com.rentmanagement.rentapi.security

import com.rentmanagement.rentapi.repository.SubscriptionRepository
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.stereotype.Component
import org.springframework.web.servlet.HandlerInterceptor
import java.time.LocalDateTime

@Component
class SubscriptionInterceptor(
    private val subscriptionRepository: SubscriptionRepository,
    private val jwtUtil: JwtUtil
) : HandlerInterceptor {

    override fun preHandle(
        request: HttpServletRequest,
        response: HttpServletResponse,
        handler: Any
    ): Boolean {

        val path = request.requestURI

        // ✅ PUBLIC / SAFE ENDPOINTS
        if (
            path.contains("/auth") ||
            path.contains("/subscriptions") ||
            path.contains("/mpesa/callback") ||
            path.contains("/payments/callback")
        ) {
            return true
        }

        val authHeader = request.getHeader("Authorization") ?: return true
        val token = authHeader.replace("Bearer ", "")

        val userId = jwtUtil.extractUserId(token)

        val sub = subscriptionRepository
            .findTopByLandlordIdOrderByCreatedAtDesc(userId)

        val isExpired =
            sub == null ||
                    sub.status != "ACTIVE" ||
                    sub.endDate?.isBefore(LocalDateTime.now()) != false
        // ✅ IF EXPIRED → allow ONLY wallet access
        if (isExpired) {

            if (path.contains("/wallet")) {
                return true
            }

            response.status = 403
            response.contentType = "application/json"
            response.writer.write("""{"error":"SUBSCRIPTION_REQUIRED"}""")

            return false
        }

        return true
    }
}