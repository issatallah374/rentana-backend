package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.math.BigDecimal
import java.util.*

@Entity
@Table(name = "platform_transactions")
data class PlatformTransaction(

    @Id
    val id: UUID,

    @Column(name = "landlord_id")
    val landlordId: UUID,

    @Column(nullable = false)
    val amount: BigDecimal,

    @Column(nullable = false)
    val reference: String
)