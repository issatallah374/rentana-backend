package com.rentmanagement.rentapi.controllers

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/admin")
class AdminApiController(
    private val jdbcTemplate: JdbcTemplate
) {

    // =========================
    // 🔐 ADMIN CHECK
    // =========================
    private fun ensureAdmin(authentication: Authentication?) {
        if (authentication == null) {
            throw RuntimeException("Unauthorized")
        }

        val roles = authentication.authorities.map { it.authority }

        if (!roles.contains("ROLE_ADMIN")) {
            throw RuntimeException("Forbidden")
        }
    }

    // =========================
    // 💸 GET PAYOUTS
    // =========================
    @GetMapping("/payouts")
    fun getPayouts(authentication: Authentication?): List<Map<String, Any>> {

        ensureAdmin(authentication)

        return jdbcTemplate.queryForList(
            """
            SELECT id, amount, destination, status, created_at
            FROM payout_requests
            WHERE status = 'PENDING'
            ORDER BY created_at DESC
            """
        )
    }

    // =========================
    // 🏦 PLATFORM WALLET
    // =========================
    @GetMapping("/platform-wallet")
    fun getPlatformWallet(authentication: Authentication?): Map<String, Any> {

        ensureAdmin(authentication)

        return jdbcTemplate.queryForMap(
            "SELECT id, balance FROM platform_wallet LIMIT 1"
        )
    }

    // =========================
    // 👤 USERS
    // =========================
    @GetMapping("/users")
    fun getUsers(authentication: Authentication?): List<Map<String, Any>> {

        ensureAdmin(authentication)

        return jdbcTemplate.queryForList(
            """
            SELECT id, full_name, email, role, is_active
            FROM users
            ORDER BY created_at DESC
            """
        )
    }
}