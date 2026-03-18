package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.SubscriptionPlan
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.util.*

interface SubscriptionPlanRepository : JpaRepository<SubscriptionPlan, UUID> {

    @Query("""
        SELECT s FROM SubscriptionPlan s 
        WHERE :amount BETWEEN s.price - 50 AND s.price + 50
    """)
    fun findMatchingPlan(@Param("amount") amount: Double): SubscriptionPlan?
}