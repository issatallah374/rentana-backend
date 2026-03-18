package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.TenancyRequest
import com.rentmanagement.rentapi.dto.TenancyResponse
import com.rentmanagement.rentapi.dto.ActiveTenantProjection
import com.rentmanagement.rentapi.dto.AllTenantProjection
import com.rentmanagement.rentapi.mapper.TenancyMapper
import com.rentmanagement.rentapi.services.TenancyService
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/tenancies")
class TenancyController(
    private val tenancyService: TenancyService
) {

    // ---------------- CREATE TENANCY ----------------

    @PostMapping
    fun create(
        @RequestBody request: TenancyRequest
    ): TenancyResponse {

        val tenancy = tenancyService.create(request)
        return TenancyMapper.toResponse(tenancy)
    }

    // ---------------- GET ACTIVE TENANTS ----------------

    @GetMapping("/active/{propertyId}")
    fun getActiveTenantsByProperty(
        @PathVariable propertyId: String
    ): List<ActiveTenantProjection> {

        return tenancyService.getActiveTenantsByProperty(propertyId)
    }

    // ---------------- GET ALL TENANTS ----------------

    @GetMapping("/property/{propertyId}")
    fun getAllTenantsByProperty(
        @PathVariable propertyId: String
    ): List<AllTenantProjection> {

        return tenancyService.getAllTenantsByProperty(propertyId)
    }

    // ---------------- DEACTIVATE TENANT ----------------

    @PutMapping("/{tenancyId}/deactivate")
    fun deactivateTenant(
        @PathVariable tenancyId: String
    ): ResponseEntity<Void> {

        tenancyService.deactivateTenancy(tenancyId)
        return ResponseEntity.ok().build()
    }

    // ---------------- ACTIVATE TENANT ----------------

    @PutMapping("/{tenancyId}/activate")
    fun activateTenant(
        @PathVariable tenancyId: String
    ): ResponseEntity<Void> {

        tenancyService.activateTenancy(tenancyId)
        return ResponseEntity.ok().build()
    }

    // ---------------- DELETE TENANCY ----------------

    @DeleteMapping("/{tenancyId}")
    fun deleteTenancy(
        @PathVariable tenancyId: String
    ): ResponseEntity<Void> {

        tenancyService.deleteTenancy(tenancyId)
        return ResponseEntity.ok().build()
    }

    @GetMapping("/{tenancyId}/financial")
    fun getTenantFinancial(
        @PathVariable tenancyId: String
    ): Map<String, Any> {

        return tenancyService.getTenantFinancialDetails(tenancyId)
    }
}