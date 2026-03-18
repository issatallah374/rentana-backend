package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.repository.DashboardSnapshotRepository
import org.springframework.web.bind.annotation.*
import java.util.*

@RestController
@RequestMapping("/api/dashboard")
class DashboardController(
    private val snapshotRepository: DashboardSnapshotRepository
) {

    @GetMapping("/history/{propertyId}")
    fun history(@PathVariable propertyId: UUID) =
        snapshotRepository.findByPropertyIdOrderByYearDescMonthDesc(propertyId)

    @GetMapping("/{propertyId}/{year}/{month}")
    fun getSnapshot(
        @PathVariable propertyId: UUID,
        @PathVariable year: Int,
        @PathVariable month: Int
    ) =
        snapshotRepository.findByPropertyIdAndYearAndMonth(propertyId, year, month)
}