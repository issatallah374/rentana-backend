package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.dto.TenancyRequest
import com.rentmanagement.rentapi.dto.ActiveTenantProjection
import com.rentmanagement.rentapi.dto.AllTenantProjection
import com.rentmanagement.rentapi.models.Tenancy
import com.rentmanagement.rentapi.repository.TenancyRepository
import com.rentmanagement.rentapi.repository.TenantRepository
import com.rentmanagement.rentapi.repository.UnitRepository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.util.UUID

@Service
class TenancyService(
    private val tenancyRepository: TenancyRepository,
    private val tenantRepository: TenantRepository,
    private val unitRepository: UnitRepository
) {

    // ---------------- CREATE TENANCY ----------------

    @Transactional
    fun create(request: TenancyRequest): Tenancy {

        val tenant = tenantRepository.findById(request.tenantId)
            .orElseThrow { RuntimeException("Tenant not found") }

        val unit = unitRepository.findById(request.unitId)
            .orElseThrow { RuntimeException("Unit not found") }

        val existingTenancy =
            tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)

        if (existingTenancy != null) {
            throw RuntimeException("Unit already occupied")
        }

        val tenancy = Tenancy(
            tenant = tenant,
            unit = unit,
            rentAmount = request.rentAmount,
            startDate = request.startDate,
            isActive = true
        )

        return tenancyRepository.save(tenancy)
    }

    // ---------------- GET ACTIVE TENANTS ----------------

    fun getActiveTenantsByProperty(
        propertyId: String
    ): List<ActiveTenantProjection> {

        return tenancyRepository.getActiveTenantsByProperty(
            UUID.fromString(propertyId)
        )
    }

    // ---------------- GET ALL TENANTS ----------------

    fun getAllTenantsByProperty(
        propertyId: String
    ): List<AllTenantProjection> {

        return tenancyRepository.getAllTenantsByProperty(
            UUID.fromString(propertyId)
        )
    }

    // ---------------- DEACTIVATE TENANCY ----------------

    @Transactional
    fun deactivateTenancy(tenancyId: String) {

        val tenancy = tenancyRepository.findById(UUID.fromString(tenancyId))
            .orElseThrow { RuntimeException("Tenancy not found") }

        tenancy.isActive = false
        tenancyRepository.save(tenancy)

        val tenant = tenancy.tenant
        tenant.isActive = false
        tenantRepository.save(tenant)
    }

    // ---------------- ACTIVATE TENANCY ----------------

    @Transactional
    fun activateTenancy(tenancyId: String) {

        val tenancy = tenancyRepository.findById(UUID.fromString(tenancyId))
            .orElseThrow { RuntimeException("Tenancy not found") }

        tenancy.isActive = true
        tenancyRepository.save(tenancy)

        val tenant = tenancy.tenant
        tenant.isActive = true
        tenantRepository.save(tenant)
    }

    //--------------FinancialTenant
    fun getTenantFinancialDetails(tenancyId: String): Map<String, Any> {

        val result = tenancyRepository.getTenantFinancialDetails(
            UUID.fromString(tenancyId)
        )

        val balance = result.balance

        val status =
            when {
                balance > 0 -> "OWING"
                balance < 0 -> "PAID_EXTRA"
                else -> "CLEARED"
            }

        return mapOf(
            "tenantName" to result.tenantName,
            "unitNumber" to result.unitNumber,
            "rentAmount" to result.rentAmount,
            "startDate" to result.startDate,
            "totalPaid" to result.totalPaid,
            "totalCharged" to result.totalCharged,
            "balance" to kotlin.math.abs(balance),
            "status" to status
        )
    }


    // ---------------- DELETE TENANCY (ARCHIVE) ----------------

    @Transactional
    fun deleteTenancy(tenancyId: String) {

        val tenancy = tenancyRepository.findById(UUID.fromString(tenancyId))
            .orElseThrow { RuntimeException("Tenancy not found") }

        tenancy.isActive = false
        tenancyRepository.save(tenancy)

        val tenant = tenancy.tenant
        tenant.isActive = false
        tenantRepository.save(tenant)
    }
}
