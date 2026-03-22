package com.rentmanagement.rentapi.controller

import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.security.core.Authentication
import org.springframework.stereotype.Controller
import org.springframework.web.bind.annotation.*
import java.util.*

@Controller
@RequestMapping("/admin")
class AdminController(
    private val jdbcTemplate: JdbcTemplate
) {

    private val log = LoggerFactory.getLogger(AdminController::class.java)

    // =====================================================
    // 🔐 LOGIN PAGE
    // =====================================================
    @GetMapping("/login")
    fun login(): String {
        return "admin/login"
    }

    // =====================================================
    // 🏠 HOME (MENU)
    // =====================================================
    @GetMapping
    fun index(): String {
        return "admin/index"
    }

    // =====================================================
    // 📊 DASHBOARD PAGE
    // =====================================================
    @GetMapping("/dashboard")
    fun dashboard(): String {
        return "admin/dashboard"
    }

    // =====================================================
    // 📄 OPTIONAL PAGES
    // =====================================================
    @GetMapping("/payouts")
    fun payouts(): String = "admin/dashboard"

    @GetMapping("/users")
    fun users(): String = "admin/dashboard"

    @GetMapping("/wallet")
    fun wallet(): String = "admin/dashboard"


    // =====================================================
    // =====================================================
    // 🔥 🔥 🔥 API SECTION (CRITICAL)
    // =====================================================
    // =====================================================

    // =====================================================
    // 💸 GET ALL PAYOUTS (ADMIN)
    // =====================================================
    @ResponseBody
    @GetMapping("/api/payouts")
    fun getAllPayouts(authentication: Authentication?): List<Map<String, Any>> {

        if (authentication == null) throw RuntimeException("Unauthorized")

        val roles = authentication.authorities.map { it.authority }
        if (!roles.contains("ROLE_ADMIN")) {
            throw RuntimeException("Forbidden")
        }

        log.info("📊 Admin fetching payouts")

        return jdbcTemplate.queryForList(
            """
            SELECT 
                p.id,
                p.property_id,
                pr.name AS property_name,
                p.landlord_id,
                u.email AS landlord_email,
                p.amount,
                p.method,
                p.destination,
                p.status,
                p.national_id,
                p.created_at,
                p.processed_at
            FROM payout_requests p
            JOIN properties pr ON pr.id = p.property_id
            JOIN users u ON u.id = p.landlord_id
            ORDER BY p.created_at DESC
            """.trimIndent()
        )
    }

    // =====================================================
    // 💰 PLATFORM WALLET
    // =====================================================
    @ResponseBody
    @GetMapping("/api/platform-wallet")
    fun getPlatformWallet(authentication: Authentication?): Map<String, Any> {

        if (authentication == null) throw RuntimeException("Unauthorized")

        val roles = authentication.authorities.map { it.authority }
        if (!roles.contains("ROLE_ADMIN")) {
            throw RuntimeException("Forbidden")
        }

        val balance = jdbcTemplate.queryForObject(
            "SELECT COALESCE(balance,0) FROM platform_wallet LIMIT 1",
            Double::class.java
        ) ?: 0.0

        return mapOf("balance" to balance)
    }
}