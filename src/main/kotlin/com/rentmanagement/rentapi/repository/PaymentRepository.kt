package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Payment
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.util.UUID

interface PaymentRepository : JpaRepository<Payment, UUID> {

    fun findByTenancy_IdOrderByPaymentDateDesc(
        tenancyId: UUID
    ): List<Payment>

    // ✅ NEW — Payments by Property
    @Query("""
        SELECT p FROM Payment p
        WHERE p.tenancy.unit.property.id = :propertyId
        ORDER BY p.paymentDate DESC
    """)
    fun findByPropertyId(
        @Param("propertyId") propertyId: UUID
    ): List<Payment>
}