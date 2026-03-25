package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.math.BigDecimal
import java.time.LocalDateTime
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
    @Column(name = "pin_hash")
    var pinHash: String? = null,

    @Column(name = "national_id")
    var nationalId: String? = null,

    @Column(name = "phone_number")
    var phoneNumber: String? = null,

    @Column(name = "otp_code")
    var otpCode: String? = null,

    @Column(name = "otp_expiry")
    var otpExpiry: LocalDateTime? = null
)