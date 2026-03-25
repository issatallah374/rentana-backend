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

            COALESCE(tb.balance, 0) AS balance,

            CASE
                WHEN COALESCE(tb.balance, 0) > 0 THEN 'OWING'
                WHEN COALESCE(tb.balance, 0) < 0 THEN 'PAID_EXTRA'
                ELSE 'CLEARED'
            END AS status

        FROM tenancies t
        JOIN units u ON u.id = t.unit_id
        JOIN tenants te ON te.id = t.tenant_id
        LEFT JOIN tenancy_balances tb ON tb.tenancy_id = t.id

        WHERE t.is_active = true
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

            COALESCE(tb.balance, 0) AS balance,

            CASE
                WHEN COALESCE(tb.balance, 0) > 0 THEN 'OWING'
                WHEN COALESCE(tb.balance, 0) < 0 THEN 'PAID_EXTRA'
                ELSE 'CLEARED'
            END AS status

        FROM tenancies t
        JOIN tenants te ON te.id = t.tenant_id
        JOIN units u ON u.id = t.unit_id
        LEFT JOIN tenancy_balances tb ON tb.tenancy_id = t.id

        WHERE u.property_id = :propertyId
        ORDER BY t.start_date DESC
    """,
        nativeQuery = true
    )

    fun getAllTenantsByProperty(
        @Param("propertyId") propertyId: UUID
    ): List<AllTenantProjection>


    // ---------------- TENANT FINANCIAL DETAILS ----------------

    @Query(
        value = """
        SELECT
            t.id as tenancyId,
            te.full_name as tenantName,
            u.unit_number as unitNumber,
            t.rent_amount as rentAmount,
            t.start_date as startDate,

            COALESCE(SUM(CASE WHEN l.entry_type='CREDIT' THEN l.amount END),0) as totalPaid,
            COALESCE(SUM(CASE WHEN l.entry_type='DEBIT' THEN l.amount END),0) as totalCharged,

            COALESCE(SUM(
                CASE
                    WHEN l.entry_type='DEBIT' THEN l.amount
                    WHEN l.entry_type='CREDIT' THEN -l.amount
                END
            ),0) as balance

        FROM tenancies t
        JOIN tenants te ON te.id = t.tenant_id
        JOIN units u ON u.id = t.unit_id
        LEFT JOIN ledger_entries l ON l.tenancy_id = t.id

        WHERE t.id = :tenancyId

        GROUP BY t.id, te.full_name, u.unit_number
        """,
        nativeQuery = true
    )
    fun getTenantFinancialDetails(
        @Param("tenancyId") tenancyId: UUID
    ): TenantFinancialProjection
}