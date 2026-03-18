package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.time.LocalDateTime
import java.util.UUID

@Entity
@Table(name = "tenants")
data class Tenant(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    var id: UUID? = null,

    @Column(name = "full_name", nullable = false)
    var fullName: String,

    @Column(name = "phone_number", nullable = false, unique = true)
    var phoneNumber: String,

    @Column(name = "is_active", nullable = false)
    var isActive: Boolean = true,

    @Column(name = "created_at", nullable = false)
    var createdAt: LocalDateTime = LocalDateTime.now()
)