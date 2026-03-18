package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Property
import com.rentmanagement.rentapi.models.Unit
import org.springframework.data.jpa.repository.JpaRepository
import java.util.UUID

interface UnitRepository : JpaRepository<Unit, UUID> {

    fun findByProperty(property: Property): List<Unit>

    fun findByReferenceNumber(referenceNumber: String): Unit?

    fun existsByAccountNumber(accountNumber: String): Boolean
}