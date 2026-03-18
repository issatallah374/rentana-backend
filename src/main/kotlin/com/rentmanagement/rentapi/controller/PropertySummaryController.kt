package com.rentmanagement.rentapi.controller

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/properties")
class PropertySummaryController(
    private val jdbcTemplate: JdbcTemplate
) {

    @GetMapping("/{id}/summary")
    fun getPropertySummary(@PathVariable id: String): Map<String, Any> {
        return jdbcTemplate.queryForMap(
            """
            SELECT *
            FROM property_summary
            WHERE property_id = ?
            """.trimIndent(),
            id
        )
    }
}