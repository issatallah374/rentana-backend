package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.TenantRequest
import com.rentmanagement.rentapi.dto.TenantResponse
import com.rentmanagement.rentapi.services.TenantService
import org.springframework.security.core.Authentication
import org.springframework.web.bind.annotation.*
import java.util.UUID

@RestController
@RequestMapping("/api/tenants")
@CrossOrigin
class TenantController(
    private val tenantService: TenantService
) {

    @GetMapping
    fun getAll(authentication: Authentication): List<TenantResponse> {

        val landlordId = UUID.fromString(authentication.name)

        return tenantService
            .getAllByLandlord(landlordId)
            .map { tenant ->
                TenantResponse(
                    id = tenant.id!!,
                    fullName = tenant.fullName,
                    phoneNumber = tenant.phoneNumber,
                    isActive = tenant.isActive
                )
            }
    }

    @PostMapping
    fun create(
        @RequestBody request: TenantRequest
    ): TenantResponse {

        val tenant = tenantService.create(request)

        return TenantResponse(
            id = tenant.id!!,
            fullName = tenant.fullName,
            phoneNumber = tenant.phoneNumber,
            isActive = tenant.isActive
        )
    }

    @PutMapping("/{id}")
    fun update(
        authentication: Authentication,
        @PathVariable id: UUID,
        @RequestBody request: TenantRequest
    ): TenantResponse {

        val landlordId = UUID.fromString(authentication.name)

        val tenant =
            tenantService.update(landlordId, id, request)

        return TenantResponse(
            id = tenant.id!!,
            fullName = tenant.fullName,
            phoneNumber = tenant.phoneNumber,
            isActive = tenant.isActive
        )
    }

    @DeleteMapping("/{id}")
    fun delete(
        authentication: Authentication,
        @PathVariable id: UUID
    ) {

        val landlordId = UUID.fromString(authentication.name)

        tenantService.delete(landlordId, id)
    }
}