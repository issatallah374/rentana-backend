package com.rentmanagement.rentapi.controller

import org.slf4j.LoggerFactory
import org.springframework.http.ResponseEntity
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
    // 🔐 AUTH HELPERS
    // =====================================================
    private fun requireAdmin(auth: Authentication?): UUID {
        if (auth == null || auth.name.isNullOrBlank()) {
            throw RuntimeException("Unauthorized")
        }

        val roles = auth.authorities.map { it.authority }
        if (!roles.contains("ROLE_ADMIN")) {
            throw RuntimeException("Forbidden")
        }

        return UUID.fromString(auth.name)
    }

    // =====================================================
    // 🔐 LOGIN PAGE
    // =====================================================
    @GetMapping("/login")
    fun login(): String = "admin/login"

    // =====================================================
    // 🏠 HOME
    // =====================================================
    @GetMapping
    fun index(): String = "admin/index"

    // =====================================================
    // 📊 DASHBOARD ROUTES
    // =====================================================
    @GetMapping("/dashboard")
    fun dashboard(): String = "admin/dashboard"

    @GetMapping("/payouts")
    fun payouts(): String = "admin/dashboard"

    @GetMapping("/users")
    fun users(): String = "admin/dashboard"

    @GetMapping("/wallet")
    fun wallet(): String = "admin/dashboard"

    // =====================================================
    // 💸 GET ALL PAYOUTS (🔥 FIXED)
    // =====================================================
    @ResponseBody
    @GetMapping("/api/payouts")
    fun getAllPayouts(auth: Authentication?): ResponseEntity<Any> {

        requireAdmin(auth)

        val data = jdbcTemplate.queryForList(
            """
            SELECT 
                p.id,
                p.property_id,
                pr.name AS property_name,
                p.landlord_id,
                u.email AS landlord_email,
                p.amount,
                p.method,
                p.status,
                p.national_id,
                p.created_at,
                p.processed_at,

                -- 🔥 WALLET DETAILS
                w.bank_name,
                w.account_number,
                w.mpesa_phone,

                -- 🔥 OPTIONAL: COMPUTED DESTINATION
                CASE 
                    WHEN p.method = 'BANK' THEN 
                        COALESCE(w.bank_name, '-') || ' (' || COALESCE(w.account_number, '-') || ')'
                    ELSE 
                        COALESCE(w.mpesa_phone, '-')
                END AS destination

            FROM payout_requests p
            JOIN properties pr ON pr.id = p.property_id
            JOIN users u ON u.id = p.landlord_id
            LEFT JOIN wallets w ON w.property_id = p.property_id

            ORDER BY p.created_at DESC
            """
        )

        return ResponseEntity.ok(data)
    }

    // =====================================================
    // 💰 PLATFORM WALLET
    // =====================================================
    @ResponseBody
    @GetMapping("/api/platform-wallet")
    fun getPlatformWallet(auth: Authentication?): ResponseEntity<Any> {

        requireAdmin(auth)

        val balance = jdbcTemplate.queryForObject(
            "SELECT COALESCE(balance,0) FROM platform_wallet LIMIT 1",
            Double::class.java
        ) ?: 0.0

        return ResponseEntity.ok(mapOf("balance" to balance))
    }
}