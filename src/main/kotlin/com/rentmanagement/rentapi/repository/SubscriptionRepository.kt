package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Subscription
import org.springframework.data.jpa.repository.JpaRepository
import java.util.*

interface SubscriptionRepository : JpaRepository<Subscription, UUID>