package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Tenant
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.util.UUID

interface TenantRepository : JpaRepository<Tenant, UUID> {

    fun findByPhoneNumber(phoneNumber: String): Tenant?

    @Query("""
        SELECT DISTINCT t
        FROM Tenancy tn
        JOIN tn.tenant t
        JOIN tn.unit u
        JOIN u.property p
        WHERE p.landlord.id = :landlordId
        AND t.isActive = true
    """)
    fun findTenantsByLandlord(
        @Param("landlordId") landlordId: UUID
    ): List<Tenant>

    @Query("""
        SELECT t
        FROM Tenancy tn
        JOIN tn.tenant t
        JOIN tn.unit u
        JOIN u.property p
        WHERE p.landlord.id = :landlordId
        AND t.id = :tenantId
    """)
    fun findTenantByLandlordAndId(
        @Param("landlordId") landlordId: UUID,
        @Param("tenantId") tenantId: UUID
    ): Tenant?
}