package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.math.BigDecimal
import java.util.UUID

@Entity
@Table(
    name = "wallets",
    uniqueConstraints = [
        UniqueConstraint(columnNames = ["property_id"])
    ]
)
class Wallet(

    @Id
    @GeneratedValue
    val id: UUID? = null,

    @OneToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "property_id", nullable = false, unique = true)
    val property: Property,

    @Column(nullable = false, precision = 19, scale = 2)
    var balance: BigDecimal = BigDecimal.ZERO,

    @Column(nullable = false)
    var autoPayoutEnabled: Boolean = false,

    @Column(nullable = false)
    var adminApprovalEnabled: Boolean = true,

    // =========================
    // EXISTING
    // =========================
    var bankName: String? = null,
    var accountNumber: String? = null,
    var mpesaPhone: String? = null,

    // =========================
    // 🔐 NEW SECURITY FIELDS
    // =========================
    var pinHash: String? = null,

    var nationalId: String? = null,

    var phoneNumber: String? = null
)