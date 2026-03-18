package com.rentmanagement.rentapi.scheduler

import com.rentmanagement.rentapi.services.DashboardSnapshotService
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Component
import org.slf4j.LoggerFactory

@Component
class RentScheduler(
    private val jdbcTemplate: JdbcTemplate,
    private val snapshotService: DashboardSnapshotService
) {

    private val log = LoggerFactory.getLogger(RentScheduler::class.java)

    // PRODUCTION MODE: run once every month (1st day at midnight)

    @Scheduled(cron = "0 0 0 1 * *")
    fun monthlyRentCycle() {

        log.info("📅 Monthly rent scheduler triggered")

        // Charge monthly rent
        jdbcTemplate.execute("SELECT charge_monthly_rent()")

        log.info("💰 Monthly rent charged")

        // Save dashboard snapshot
        snapshotService.createMonthlySnapshots()

        log.info("📸 Monthly dashboard snapshot saved")
    }
}