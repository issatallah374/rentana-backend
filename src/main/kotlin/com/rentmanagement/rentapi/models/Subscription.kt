package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.time.LocalDateTime
import java.util.UUID

@Entity
@Table(name = "subscriptions")
data class Subscription(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    var id: UUID? = null,

    @Column(name = "landlord_id", nullable = false)
    var landlordId: UUID,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "plan_id", nullable = false)
    var plan: SubscriptionPlan,

    @Column(name = "start_date")
    var startDate: LocalDateTime? = null,

    @Column(name = "end_date")
    var endDate: LocalDateTime? = null,

    @Column(nullable = false)
    var status: String = "ACTIVE",

    @Column(name = "created_at")
    var createdAt: LocalDateTime = LocalDateTime.now()
)