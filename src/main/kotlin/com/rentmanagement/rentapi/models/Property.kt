package com.rentmanagement.rentapi.models

import com.fasterxml.jackson.annotation.JsonIgnore
import jakarta.persistence.*
import java.time.LocalDateTime
import java.util.UUID

@Entity
@Table(name = "properties")
data class Property(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(nullable = false)
    val name: String,

    @Column(nullable = false)
    val address: String,

    @Column(nullable = false)
    val city: String,

    @Column(nullable = false)
    val country: String,

    // ADD THIS FIELD (required for repository query)
    @Column(name = "account_prefix", unique = true, nullable = false)
    var accountPrefix: String,

    // landlord relationship
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "landlord_id", nullable = false)
    @JsonIgnore
    val landlord: User,

    @Column(name = "created_at", nullable = false)
    val createdAt: LocalDateTime = LocalDateTime.now()
)
