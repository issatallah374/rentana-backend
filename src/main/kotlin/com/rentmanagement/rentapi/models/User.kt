package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.time.LocalDateTime
import java.util.UUID

@Entity
@Table(
    name = "users",
    uniqueConstraints = [
        UniqueConstraint(columnNames = ["email"]),
        UniqueConstraint(columnNames = ["phone"])
    ]
)
data class User(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    var id: UUID? = null,

    @Column(name = "full_name", nullable = false)
    var fullName: String,

    @Column(nullable = false)
    var email: String,

    // 🔥 IMPORTANT FOR LOGIN + MPESA
    @Column(nullable = false)
    var phone: String,

    @Column(name = "password_hash", nullable = false)
    var passwordHash: String,

    // 🔐 NEW: USER PIN (HASHED)
    @Column(name = "pin_hash")
    var pinHash: String? = null,

    @Column(nullable = false)
    var role: String,

    @Column(name = "is_active", nullable = false)
    var isActive: Boolean = true,

    @Column(name = "created_at", nullable = false)
    var createdAt: LocalDateTime = LocalDateTime.now(),

    // 🔐 ADMIN SECURITY (ALREADY GOOD)
    @Column(name = "national_id_hash")
    var nationalIdHash: String? = null

) {

    // =========================
    // 📱 NORMALIZE PHONE
    // =========================
    @PrePersist
    @PreUpdate
    fun normalizePhone() {
        phone = when {
            phone.startsWith("254") -> "0" + phone.substring(3)
            phone.startsWith("+254") -> "0" + phone.substring(4)
            else -> phone
        }
    }
}