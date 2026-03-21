package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.math.BigDecimal
import java.time.LocalDateTime
import java.util.*

@Entity
@Table(name = "dashboard_snapshots")
data class DashboardSnapshot(

    @Id
    val id: UUID = UUID.randomUUID(),

    @Column(name = "property_id", nullable = false)
    val propertyId: UUID,

    @Column(nullable = false)
    val year: Int,

    @Column(nullable = false)
    val month: Int,

    @Column(name = "rent_expected", nullable = false)
    val rentExpected: BigDecimal,

    @Column(name = "rent_collected", nullable = false)
    val rentCollected: BigDecimal,

    @Column(nullable = false)
    val arrears: BigDecimal,

    // ✅ KEEP THIS — required for sorting, audit, analytics
    @Column(name = "created_at", nullable = false)
    val createdAt: LocalDateTime = LocalDateTime.now()
)