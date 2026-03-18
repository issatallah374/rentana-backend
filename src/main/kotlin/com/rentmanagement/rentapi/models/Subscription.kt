package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.time.LocalDateTime
import java.util.*

@Entity
@Table(name = "subscriptions")
data class Subscription(

    @Id
    val id: UUID,

    @Column(name = "landlord_id")
    val landlordId: UUID,

    @Column(name = "plan_id")
    val planId: UUID,

    @Column(name = "start_date")
    val startDate: LocalDateTime,

    @Column(name = "end_date")
    val endDate: LocalDateTime,

    val status: String
)