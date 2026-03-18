package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.time.LocalDateTime
import java.util.UUID
import java.math.BigDecimal

@Entity
@Table(
    name = "units",
    uniqueConstraints = [
        UniqueConstraint(columnNames = ["account_number"])
    ]
)
data class Unit(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(name = "unit_number", nullable = false)
    val unitNumber: String,

    @Column(name = "account_number", nullable = false, unique = true)
    val accountNumber: String,

    @Column(name = "reference_number", nullable = false) // Add referenceNumber column
    val referenceNumber: String, // Add referenceNumber field here

    @Column(name = "rent_amount", nullable = false)
    var rentAmount: BigDecimal,

    @Column(nullable = false)
    val isActive: Boolean = true,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "property_id", nullable = false)
    val property: Property,

    @Column(name = "created_at", nullable = false)
    val createdAt: LocalDateTime = LocalDateTime.now()
)
