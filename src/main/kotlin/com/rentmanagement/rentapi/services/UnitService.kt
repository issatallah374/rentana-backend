package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.dto.AssignTenantRequest
import com.rentmanagement.rentapi.models.Tenant
import com.rentmanagement.rentapi.models.Tenancy
import com.rentmanagement.rentapi.repository.TenantRepository
import com.rentmanagement.rentapi.repository.TenancyRepository
import com.rentmanagement.rentapi.repository.UnitRepository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.util.UUID

@Service
class UnitService(
    private val unitRepository: UnitRepository,
    private val tenantRepository: TenantRepository,
    private val tenancyRepository: TenancyRepository
) {

    @Transactional
    fun assignTenant(unitId: UUID, request: AssignTenantRequest) {

        val unit = unitRepository.findById(unitId)
            .orElseThrow { RuntimeException("Unit not found") }

        // ===============================
        // 🔥 DEACTIVATE OLD TENANCY
        // ===============================
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

        // ===============================
        // 🔥 CREATE NEW TENANT
        // ===============================
        val newTenant = Tenant(
            fullName = request.fullName,
            phoneNumber = request.phoneNumber,
            isActive = true
        )

        val savedTenant = tenantRepository.save(newTenant)

        // ===============================
        // 🔥 CREATE NEW TENANCY
        // ===============================
        val newTenancy = Tenancy(
            tenant = savedTenant,
            unit = unit,
            rentAmount = unit.rentAmount,
            startDate = request.startDate,
            isActive = true
        )

        tenancyRepository.save(newTenancy)

        // ===============================
        // ❌ NO RENT CHARGE HERE
        // ===============================
        // Rent will be charged ONLY by:
        // ✅ SQL function: charge_monthly_rent()
    }
}