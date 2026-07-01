package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.dto.MonthlyTenantReportDto
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.util.*

@Service
class ReportService(
    private val jdbcTemplate: JdbcTemplate
) {

    // =====================================================
    // 📊 MONTHLY TENANT REPORT
    // =====================================================
    fun getMonthlyTenantReport(
        propertyId: UUID,
        month: Int,
        year: Int
    ): List<MonthlyTenantReportDto> {

        val sql = """
            SELECT
                t.id AS tenancy_id,

                COALESCE(
                    te.full_name,
                    'Unknown Tenant'
                ) AS tenant_name,

                COALESCE(
                    u.unit_number,
                    'Unknown Unit'
                ) AS unit_name,

                p.id AS property_id,

                ? AS month,

                ? AS year,

                -- =========================================
                -- 💰 RENT CHARGED
                -- =========================================
                COALESCE(
                    SUM(
                        CASE
                            WHEN l.entry_type = 'DEBIT'
                            AND l.category = 'MONTHLY_RENT'
                            THEN l.amount

                            ELSE 0
                        END
                    ),
                    0
                ) AS rent_charged,

                -- =========================================
                -- 💳 PAYMENTS RECEIVED
                -- =========================================
                COALESCE(
                    SUM(
                        CASE
                            WHEN l.entry_type = 'CREDIT'
                            AND l.category = 'RENT_PAYMENT'
                            THEN l.amount

                            ELSE 0
                        END
                    ),
                    0
                ) AS amount_paid

            FROM tenancies t

            JOIN tenants te
                ON t.tenant_id = te.id

            JOIN units u
                ON t.unit_id = u.id

            JOIN properties p
                ON u.property_id = p.id

            LEFT JOIN ledger_entries l
                ON l.tenancy_id = t.id
                AND l.entry_month = ?
                AND l.entry_year = ?

            WHERE p.id = ?
              AND t.is_active = true

            GROUP BY
                t.id,
                te.full_name,
                u.unit_number,
                p.id

            ORDER BY
                u.unit_number ASC
        """.trimIndent()

        return jdbcTemplate.query(
            sql,
            { rs, _ ->

                val rentCharged =
                    rs.getBigDecimal("rent_charged")
                        ?: BigDecimal.ZERO

                val amountPaid =
                    rs.getBigDecimal("amount_paid")
                        ?: BigDecimal.ZERO

                val balance =
                    rentCharged.subtract(amountPaid)

                // =========================================
                // 📌 PAYMENT STATUS
                // =========================================
                val status = when {

                    rentCharged <= BigDecimal.ZERO ->
                        "NO_CHARGE"

                    balance <= BigDecimal.ZERO ->
                        "PAID"

                    amountPaid > BigDecimal.ZERO ->
                        "PARTIAL"

                    else ->
                        "UNPAID"
                }

                MonthlyTenantReportDto(

                    tenancyId = UUID.fromString(
                        rs.getString("tenancy_id")
                    ),

                    tenantName =
                        rs.getString("tenant_name"),

                    unitName =
                        rs.getString("unit_name"),

                    propertyId = UUID.fromString(
                        rs.getString("property_id")
                    ),

                    month =
                        rs.getInt("month"),

                    year =
                        rs.getInt("year"),

                    rentCharged =
                        rentCharged,

                    amountPaid =
                        amountPaid,

                    balance =
                        balance,

                    status =
                        status
                )
            },

            month,
            year,
            month,
            year,
            propertyId
        )
    }
}