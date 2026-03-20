package com.rentmanagement.rentapi.controllers

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/admin")
class AdminApiController(
    private val jdbcTemplate: JdbcTemplate
) {

    @GetMapping("/payouts")
    fun getPayouts(): List<Map<String, Any>> {

        return jdbcTemplate.queryForList(
            """
            SELECT id, amount, destination, status
            FROM payout_requests
            WHERE status = 'PENDING'
            ORDER BY created_at DESC
            """
        )
    }

    @GetMapping("/platform-wallet")
    fun getPlatformWallet(): Map<String, Any> {

        return jdbcTemplate.queryForMap(
            "SELECT * FROM platform_wallet LIMIT 1"
        )
    }
}