package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Tenancy
import com.rentmanagement.rentapi.dto.ActiveTenantProjection
import com.rentmanagement.rentapi.dto.AllTenantProjection
import com.rentmanagement.rentapi.dto.TenantFinancialProjection
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.util.UUID

interface TenancyRepository : JpaRepository<Tenancy, UUID> {

    fun findByUnitIdAndIsActiveTrue(unitId: UUID): Tenancy?

    // ---------------- ACTIVE TENANTS ----------------

    @Query(
        value = """
        SELECT 
            t.id AS tenancyId,
            u.id AS unitId,
            u.unit_number AS unitNumber,
            te.full_name AS tenantName,
            te.phone_number AS tenantPhone,

            COALESCE((
                SELECT SUM(
                    CASE
                        WHEN le.entry_type = 'DEBIT' THEN le.amount
                        WHEN le.entry_type = 'CREDIT' THEN -le.amount
                    END
                )
                FROM ledger_entries le
                WHERE le.tenancy_id = t.id
            ), 0) AS balance,

            CASE
                WHEN COALESCE((
                    SELECT SUM(
                        CASE
                            WHEN le.entry_type = 'DEBIT' THEN le.amount
                            WHEN le.entry_type = 'CREDIT' THEN -le.amount
                        END
                    )
                    FROM ledger_entries le
                    WHERE le.tenancy_id = t.id
                ), 0) > 0 THEN 'OWING'

                WHEN COALESCE((
                    SELECT SUM(
                        CASE
                            WHEN le.entry_type = 'DEBIT' THEN le.amount
                            WHEN le.entry_type = 'CREDIT' THEN -le.amount
                        END
                    )
                    FROM ledger_entries le
                    WHERE le.tenancy_id = t.id
                ), 0) < 0 THEN 'PAID_EXTRA'

                ELSE 'CLEARED'
            END AS status

        FROM tenancies t
        JOIN units u ON u.id = t.unit_id
        JOIN tenants te ON te.id = t.tenant_id

        WHERE t.is_active = true
          AND t.start_date <= CURRENT_DATE
          AND u.property_id = :propertyId

        ORDER BY u.unit_number
        """,
        nativeQuery = true
    )
    fun getActiveTenantsByProperty(
        @Param("propertyId") propertyId: UUID
    ): List<ActiveTenantProjection>


    // ---------------- ALL TENANTS ----------------

    @Query(
        value = """
        SELECT
            t.id AS tenancyId,
            te.full_name AS tenantName,
            te.phone_number AS tenantPhone,
            u.unit_number AS unitNumber,
            t.start_date AS startDate,
            t.is_active AS active,

            COALESCE((
                SELECT SUM(
                    CASE
                        WHEN le.entry_type = 'DEBIT' THEN le.amount
                        WHEN le.entry_type = 'CREDIT' THEN -le.amount
                    END
                )
                FROM ledger_entries le
                WHERE le.tenancy_id = t.id
            ), 0) AS balance,

            CASE
                WHEN COALESCE((
                    SELECT SUM(
                        CASE
                            WHEN le.entry_type = 'DEBIT' THEN le.amount
                            WHEN le.entry_type = 'CREDIT' THEN -le.amount
                        END
                    )
                    FROM ledger_entries le
                    WHERE le.tenancy_id = t.id
                ), 0) > 0 THEN 'OWING'

                WHEN COALESCE((
                    SELECT SUM(
                        CASE
                            WHEN le.entry_type = 'DEBIT' THEN le.amount
                            WHEN le.entry_type = 'CREDIT' THEN -le.amount
                        END
                    )
                    FROM ledger_entries le
                    WHERE le.tenancy_id = t.id
                ), 0) < 0 THEN 'PAID_EXTRA'

                ELSE 'CLEARED'
            END AS status

        FROM tenancies t
        JOIN tenants te ON te.id = t.tenant_id
        JOIN units u ON u.id = t.unit_id

        WHERE u.property_id = :propertyId
        ORDER BY t.start_date DESC
        """,
        nativeQuery = true
    )
    fun getAllTenantsByProperty(
        @Param("propertyId") propertyId: UUID
    ): List<AllTenantProjection>


    // ---------------- TENANT FINANCIAL DETAILS (🔥 FIXED) ----------------

    @Query(
        value = """
        SELECT
            t.id as tenancyId,
            te.full_name as tenantName,
            u.unit_number as unitNumber,
            t.rent_amount as rentAmount,
            t.start_date as startDate,

            -- ✅ FIX: NO JOIN (prevents duplication)
            COALESCE((
                SELECT SUM(l.amount)
                FROM ledger_entries l
                WHERE l.tenancy_id = t.id
                AND l.entry_type = 'CREDIT'
            ), 0) as totalPaid,

            COALESCE((
                SELECT SUM(l.amount)
                FROM ledger_entries l
                WHERE l.tenancy_id = t.id
                AND l.entry_type = 'DEBIT'
            ), 0) as totalCharged,

            COALESCE((
                SELECT SUM(
                    CASE
                        WHEN l.entry_type = 'DEBIT' THEN l.amount
                        WHEN l.entry_type = 'CREDIT' THEN -l.amount
                    END
                )
                FROM ledger_entries l
                WHERE l.tenancy_id = t.id
            ), 0) as balance

        FROM tenancies t
        JOIN tenants te ON te.id = t.tenant_id
        JOIN units u ON u.id = t.unit_id

        WHERE t.id = :tenancyId
        """,
        nativeQuery = true
    )
    fun getTenantFinancialDetails(
        @Param("tenancyId") tenancyId: UUID
    ): TenantFinancialProjection
}
