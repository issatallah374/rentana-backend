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

    fun countByLandlord(landlord: User): Int

    fun countByLandlordId(landlordId: UUID): Int

    // ===============================
    // DASHBOARD / REPORTING
    // ===============================
    @Query(
        value = """
            SELECT 
                p.id as propertyId,

                COUNT(DISTINCT u.id) as totalUnits,

                COUNT(DISTINCT t.id) FILTER (
                    WHERE t.is_active = true
                ) as activeTenancies,

                COALESCE(SUM(
                    CASE 
                        WHEN l.entry_type = 'DEBIT'
                         AND l.entry_year = EXTRACT(YEAR FROM CURRENT_DATE)::int
                         AND l.entry_month = EXTRACT(MONTH FROM CURRENT_DATE)::int
                        THEN l.amount
                        ELSE 0
                    END
                ), 0) as totalExpected,

                (
                    COALESCE(SUM(
                        CASE 
                            WHEN l.entry_type = 'CREDIT'
                             AND l.entry_year = EXTRACT(YEAR FROM CURRENT_DATE)::int
                             AND l.entry_month = EXTRACT(MONTH FROM CURRENT_DATE)::int
                            THEN l.amount
                            ELSE 0
                        END
                    ), 0)
                    -
                    COALESCE((
                        SELECT SUM(da.amount)
                        FROM dashboard_adjustments da
                        WHERE da.property_id = p.id
                          AND da.year = EXTRACT(YEAR FROM CURRENT_DATE)::int
                          AND da.month = EXTRACT(MONTH FROM CURRENT_DATE)::int
                          AND da.metric = 'RECEIVED_REDUCTION'
                    ), 0)
                ) as totalCollected

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