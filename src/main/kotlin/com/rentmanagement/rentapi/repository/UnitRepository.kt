package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Property
import com.rentmanagement.rentapi.models.Unit
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.util.UUID

interface UnitRepository : JpaRepository<Unit, UUID> {

    fun findByProperty(property: Property): List<Unit>

    fun findByReferenceNumber(referenceNumber: String): Unit?

    fun existsByAccountNumber(accountNumber: String): Boolean

    // 🔥 NEW — NORMALIZED MATCH (CRITICAL FOR PAYMENTS)
    @Query("""
        SELECT u FROM Unit u
        WHERE UPPER(REPLACE(REPLACE(u.referenceNumber, '-', ''), ' ', '')) =
              UPPER(REPLACE(REPLACE(:reference, '-', ''), ' ', ''))
    """)
    fun findByReferenceNumberIgnoreCase(
        @Param("reference") reference: String
    ): Unit?
}