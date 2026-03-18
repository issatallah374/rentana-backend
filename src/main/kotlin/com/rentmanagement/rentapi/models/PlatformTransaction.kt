package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.time.LocalDateTime
import java.util.*

@Entity
@Table(name = "platform_transactions")
data class PlatformTransaction(

    @Id
    val id: UUID,

    @Column(name = "landlord_id")
    val landlordId: UUID,

    val amount: Double,

    val reference: String,

    @Column(name = "created_at")
    val createdAt: LocalDateTime = LocalDateTime.now()
)