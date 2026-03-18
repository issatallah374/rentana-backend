package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.time.LocalDate
import java.util.UUID
import java.math.BigDecimal

@Entity
@Table(name = "tenancies")
class Tenancy(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @ManyToOne
    @JoinColumn(name = "tenant_id", nullable = false)
    val tenant: Tenant,

    @ManyToOne
    @JoinColumn(name = "unit_id", nullable = false)
    val unit: Unit,

    @Column(
        name = "rent_amount",
        nullable = false,
        precision = 19,
        scale = 2
    )
    var rentAmount: BigDecimal,

    @Column(nullable = false)
    var startDate: LocalDate,

    @Column(name = "is_active", nullable = false)
    var isActive: Boolean = true
)