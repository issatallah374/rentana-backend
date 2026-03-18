package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.DashboardSnapshot
import org.springframework.data.jpa.repository.JpaRepository
import java.util.*

interface DashboardSnapshotRepository : JpaRepository<DashboardSnapshot, UUID> {

    fun findByPropertyIdOrderByYearDescMonthDesc(propertyId: UUID): List<DashboardSnapshot>

    fun findByPropertyIdAndYearAndMonth(
        propertyId: UUID,
        year: Int,
        month: Int
    ): DashboardSnapshot?
}