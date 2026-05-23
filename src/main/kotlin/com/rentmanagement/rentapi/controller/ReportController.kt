package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.MonthlyTenantReportDto
import com.rentmanagement.rentapi.services.ReportService
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController
import java.util.*

@RestController
@RequestMapping("/api/reports")
class ReportController(
    private val reportService: ReportService
) {

    // =====================================================
    // 📊 MONTHLY PROPERTY REPORT
    // =====================================================
    @GetMapping("/monthly")
    fun getMonthlyReport(

        @RequestParam
        propertyId: UUID,

        @RequestParam
        month: Int,

        @RequestParam
        year: Int

    ): List<MonthlyTenantReportDto> {

        require(month in 1..12) {
            "Month must be between 1 and 12"
        }

        require(year >= 2020) {
            "Invalid year"
        }

        return reportService.getMonthlyTenantReport(
            propertyId = propertyId,
            month = month,
            year = year
        )
    }
}