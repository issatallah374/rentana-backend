package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.math.BigDecimal
import java.util.UUID

@Entity
@Table(
    name = "wallets",
    uniqueConstraints = [
        UniqueConstraint(columnNames = ["property_id"]) // ✅ enforce 1 wallet per property
    ]
)
class Wallet(

    @Id
    @GeneratedValue
    val id: UUID? = null,

    // ✅ Many wallets can belong to one landlord (correct)
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "landlord_id", nullable = false)
    val landlord: User,

    // 🔥 CRITICAL: enforce 1 wallet per property
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "property_id", nullable = false)
    val property: Property,

    @Column(nullable = false, precision = 19, scale = 2)
    var balance: BigDecimal = BigDecimal.ZERO,

    @Column(nullable = false)
    var autoPayoutEnabled: Boolean = false,

    @Column(nullable = false)
    var adminApprovalEnabled: Boolean = true
)