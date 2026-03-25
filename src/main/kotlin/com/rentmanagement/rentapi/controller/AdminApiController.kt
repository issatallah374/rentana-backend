package com.rentmanagement.rentapi.controller

import org.slf4j.LoggerFactory
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import java.util.*

@RestController
@RequestMapping("/api/admin")
class AdminApiController(
    private val jdbcTemplate: JdbcTemplate
) {

    private val log = LoggerFactory.getLogger(AdminApiController::class.java)

    // =========================
    // 🔐 ADMIN CHECK
    // =========================
    private fun ensureAdmin(authentication: Authentication?): UUID {
        if (authentication == null || authentication.name.isNullOrBlank()) {
            throw RuntimeException("Unauthorized")
        }

        val roles = authentication.authorities.map { it.authority }

        if (!roles.contains("ROLE_ADMIN")) {
            throw RuntimeException("Forbidden")
        }

        return UUID.fromString(authentication.name)
    }

    // =========================
    // 💸 GET PAYOUTS (🔥 FULL SAFE)
    // =========================
    @GetMapping("/payouts")
    fun getPayouts(authentication: Authentication?): List<Map<String, Any>> {

        ensureAdmin(authentication)

        log.info("🔥 Fetching admin payouts...")

        return jdbcTemplate.queryForList(
            """
            SELECT 
                p.id,
                p.property_id,

                COALESCE(pr.name, p.property_id::text) AS property_name,

                p.landlord_id,
                COALESCE(u.email, '-') AS landlord_email,

                p.amount,
                p.method,
                p.status,
                p.created_at,
                p.processed_at,

                CASE 
                    WHEN p.method = 'BANK' THEN 
                        COALESCE(w.bank_name, '-') || ' (' || COALESCE(w.account_number, '-') || ')'
                    ELSE 
                        COALESCE(w.mpesa_phone, '-')
                END AS destination

            FROM payout_requests p

            -- 🔥 SAFE JOINS (NO CRASH)
            LEFT JOIN properties pr ON pr.id = p.property_id
            LEFT JOIN users u ON u.id = p.landlord_id
            LEFT JOIN wallets w ON w.property_id = p.property_id

            ORDER BY p.created_at DESC
            """
        )
    }

    // =========================
    // 🏦 PLATFORM WALLET (SAFE)
    // =========================
    @GetMapping("/platform-wallet")
    fun getPlatformWallet(authentication: Authentication?): Map<String, Any> {

        ensureAdmin(authentication)

        return try {
            jdbcTemplate.queryForMap(
                "SELECT id, COALESCE(balance,0) as balance FROM platform_wallet LIMIT 1"
            )
        } catch (e: Exception) {
            log.error("❌ Platform wallet failed", e)
            mapOf("balance" to 0)
        }
    }

    // =========================
    // 👤 USERS (SAFE)
    // =========================
    @GetMapping("/users")
    fun getUsers(authentication: Authentication?): List<Map<String, Any>> {

        ensureAdmin(authentication)

        return jdbcTemplate.queryForList(
            """
            SELECT 
                id,
                COALESCE(full_name, '-') as full_name,
                email,
                role,
                is_active
            FROM users
            ORDER BY created_at DESC
            """
        )
    }
}