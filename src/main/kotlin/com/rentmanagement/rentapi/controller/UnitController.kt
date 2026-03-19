package com.rentmanagement.rentapi.controllers

import com.rentmanagement.rentapi.dto.AssignTenantRequest
import com.rentmanagement.rentapi.dto.UnitDetailsResponse
import com.rentmanagement.rentapi.dto.UnitRequest
import com.rentmanagement.rentapi.dto.UnitSummaryResponse
import com.rentmanagement.rentapi.models.Unit
import com.rentmanagement.rentapi.repository.PropertyRepository
import com.rentmanagement.rentapi.repository.TenancyRepository
import com.rentmanagement.rentapi.repository.UnitRepository
import com.rentmanagement.rentapi.services.UnitService
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*
import java.util.UUID

@RestController
@RequestMapping("/api/units")
class UnitController(
    private val unitRepository: UnitRepository,
    private val propertyRepository: PropertyRepository,
    private val unitService: UnitService,
    private val tenancyRepository: TenancyRepository
) {

    // =====================================================
    // 🔥 CREATE UNIT (FIXED — NO DASHES)
    // =====================================================

    @PostMapping
    fun createUnit(
        @RequestBody request: UnitRequest
    ): ResponseEntity<UnitDetailsResponse> {

        val property = propertyRepository.findById(UUID.fromString(request.propertyId))
            .orElseThrow { RuntimeException("Property not found") }

        // 🔥 CLEAN UNIT NUMBER (digits only)
        val cleanUnitNumber = request.unitNumber.filter { it.isLetterOrDigit() }

        // 🔥 FINAL ACCOUNT → K2 (NO DASH)
        val referenceNumber = "${property.accountPrefix}$cleanUnitNumber"

        if (unitRepository.existsByAccountNumber(referenceNumber)) {
            throw RuntimeException("Unit already exists")
        }

        val unit = Unit(
            unitNumber = request.unitNumber,
            accountNumber = referenceNumber,   // ✅ SAME
            referenceNumber = referenceNumber, // ✅ SAME
            rentAmount = request.rentAmount,
            property = property
        )

        val saved = unitRepository.save(unit)

        return ResponseEntity.ok(
            UnitDetailsResponse(
                id = saved.id!!,
                unitNumber = saved.unitNumber,
                rentAmount = saved.rentAmount,
                accountNumber = saved.referenceNumber, // 🔥 FORCE CLEAN
                referenceNumber = saved.referenceNumber,
                isActive = saved.isActive
            )
        )
    }

    // =====================================================
    // GET UNITS BY PROPERTY
    // =====================================================

    @GetMapping("/property/{propertyId}")
    fun getUnits(@PathVariable propertyId: String): ResponseEntity<List<UnitSummaryResponse>> {

        val property = propertyRepository.findById(UUID.fromString(propertyId))
            .orElseThrow { RuntimeException("Property not found") }

        val units = unitRepository.findByProperty(property).map { unit ->

            val activeTenancy =
                tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)

            UnitSummaryResponse(
                id = unit.id!!,
                unitNumber = unit.unitNumber,
                rentAmount = unit.rentAmount,
                accountNumber = unit.referenceNumber, // 🔥 ALWAYS CLEAN
                tenantName = activeTenancy?.tenant?.fullName,
                isOccupied = activeTenancy != null
            )
        }

        return ResponseEntity.ok(units)
    }

    // =====================================================
    // GET SINGLE UNIT
    // =====================================================

    @GetMapping("/{unitId}")
    fun getUnitById(
        @PathVariable unitId: String
    ): ResponseEntity<UnitDetailsResponse> {

        val unit = unitRepository.findById(UUID.fromString(unitId))
            .orElseThrow { RuntimeException("Unit not found") }

        val activeTenancy =
            tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)

        return ResponseEntity.ok(
            UnitDetailsResponse(
                id = unit.id!!,
                unitNumber = unit.unitNumber,
                rentAmount = unit.rentAmount,
                accountNumber = unit.referenceNumber, // 🔥 FORCE CLEAN
                referenceNumber = unit.referenceNumber,
                isActive = unit.isActive,
                tenantName = activeTenancy?.tenant?.fullName,
                tenantPhone = activeTenancy?.tenant?.phoneNumber,
                isOccupied = activeTenancy != null,
                tenancyId = activeTenancy?.id,
                tenancyActive = activeTenancy?.isActive
            )
        )
    }

    // =====================================================
    // ASSIGN TENANT
    // =====================================================

    @PostMapping("/{unitId}/assign")
    fun assignTenant(
        @PathVariable unitId: String,
        @RequestBody request: AssignTenantRequest
    ): ResponseEntity<UnitDetailsResponse> {

        unitService.assignTenant(UUID.fromString(unitId), request)

        val unit = unitRepository.findById(UUID.fromString(unitId))
            .orElseThrow { RuntimeException("Unit not found") }

        val activeTenancy =
            tenancyRepository.findByUnitIdAndIsActiveTrue(unit.id!!)

        return ResponseEntity.ok(
            UnitDetailsResponse(
                id = unit.id!!,
                unitNumber = unit.unitNumber,
                rentAmount = unit.rentAmount,
                accountNumber = unit.referenceNumber, // 🔥 FORCE CLEAN
                referenceNumber = unit.referenceNumber,
                isActive = unit.isActive,
                tenantName = activeTenancy?.tenant?.fullName,
                tenantPhone = activeTenancy?.tenant?.phoneNumber,
                isOccupied = activeTenancy != null,
                tenancyId = activeTenancy?.id,
                tenancyActive = activeTenancy?.isActive
            )
        )
    }
}