package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Property
import com.rentmanagement.rentapi.models.User
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.util.UUID

interface PropertyRepository : JpaRepository<Property, UUID> {

    // ===============================
    // BASIC OPERATIONS
    // ===============================

    fun findByLandlord(landlord: User): List<Property>

    fun findByAccountPrefix(accountPrefix: String): Property?

    fun existsByAccountPrefix(accountPrefix: String): Boolean


    // ===============================
    // DASHBOARD / REPORTING
    // ===============================

    @Query(
        value = """
            SELECT 
                p.id as propertyId,
                COUNT(DISTINCT u.id) as totalUnits,
                COUNT(DISTINCT t.id) FILTER (WHERE t.active = true) as activeTenancies,
                COALESCE(SUM(
                    CASE 
                        WHEN l.entry_type = 'DEBIT' THEN l.amount
                    END
                ), 0) as totalExpected,
                COALESCE(SUM(
                    CASE 
                        WHEN l.entry_type = 'CREDIT' THEN l.amount
                    END
                ), 0) as totalCollected
            FROM properties p
            LEFT JOIN units u ON u.property_id = p.id
            LEFT JOIN tenancies t ON t.unit_id = u.id
            LEFT JOIN ledger_entries l ON l.tenancy_id = t.id
            WHERE p.id = :propertyId
            GROUP BY p.id
        """,
        nativeQuery = true
    )
    fun getPropertySummary(
        @Param("propertyId") propertyId: UUID
    ): PropertySummaryProjection?
}