package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.dto.AssignTenantRequest
import com.rentmanagement.rentapi.models.LedgerEntry
import com.rentmanagement.rentapi.models.LedgerCategory
import com.rentmanagement.rentapi.models.LedgerEntryType
import com.rentmanagement.rentapi.models.Tenant
import com.rentmanagement.rentapi.models.Tenancy
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.repository.TenantRepository
import com.rentmanagement.rentapi.repository.TenancyRepository
import com.rentmanagement.rentapi.repository.UnitRepository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.LocalDateTime
import java.util.UUID

@Service
class UnitService(
    private val unitRepository: UnitRepository,
    private val tenantRepository: TenantRepository,
    private val tenancyRepository: TenancyRepository,
    private val ledgerEntryRepository: LedgerEntryRepository
) {

    @Transactional
    fun assignTenant(unitId: UUID, request: AssignTenantRequest) {

        val unit = unitRepository.findById(unitId)
            .orElseThrow { RuntimeException("Unit not found") }

        // 🔥 Deactivate old tenancy if exists
        val existingTenancy =
            tenancyRepository.findByUnitIdAndIsActiveTrue(unitId)

        if (existingTenancy != null) {

            existingTenancy.isActive = false
            tenancyRepository.save(existingTenancy)

            val oldTenant = existingTenancy.tenant
            oldTenant.isActive = false
            tenantRepository.save(oldTenant)

            tenancyRepository.flush()
        }

        // 🔥 Create new tenant
        val newTenant = Tenant(
            fullName = request.fullName,
            phoneNumber = request.phoneNumber,
            isActive = true
        )

        val savedTenant = tenantRepository.save(newTenant)

        // 🔥 Create new tenancy
        val newTenancy = Tenancy(
            tenant = savedTenant,
            unit = unit,
            rentAmount = unit.rentAmount,
            startDate = request.startDate,
            isActive = true
        )

        val savedTenancy = tenancyRepository.save(newTenancy)

        // =====================================================
        // 🔥 CREATE INITIAL RENT CHARGE
        // =====================================================

        val rentCharge = LedgerEntry(
            property = unit.property,
            tenancy = savedTenancy,
            entryType = LedgerEntryType.DEBIT,
            category = LedgerCategory.RENT_CHARGE,
            amount = unit.rentAmount,
            referenceId = savedTenancy.id,
            createdAt = LocalDateTime.now()
        )

        ledgerEntryRepository.save(rentCharge)
    }
}