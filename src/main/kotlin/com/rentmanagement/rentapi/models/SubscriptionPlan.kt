package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.util.*

@Entity
@Table(name = "subscription_plans")
data class SubscriptionPlan(

    @Id
    val id: UUID,

    val name: String,

    val price: Double,

    @Column(name = "property_limit")
    val propertyLimit: Int
)