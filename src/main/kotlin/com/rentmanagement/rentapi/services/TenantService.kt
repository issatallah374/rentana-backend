package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.dto.TenantRequest
import com.rentmanagement.rentapi.models.Tenant
import com.rentmanagement.rentapi.repository.TenantRepository
import org.springframework.stereotype.Service
import java.util.UUID

@Service
class TenantService(
    private val tenantRepository: TenantRepository
) {

    fun create(request: TenantRequest): Tenant {

        val existing =
            tenantRepository.findByPhoneNumber(request.phoneNumber)

        if (existing != null) {
            throw RuntimeException("Tenant with this phone already exists")
        }

        val tenant = Tenant(
            fullName = request.fullName,
            phoneNumber = request.phoneNumber,
            isActive = true
        )

        return tenantRepository.save(tenant)
    }

    fun getAllByLandlord(landlordId: UUID): List<Tenant> {
        return tenantRepository.findTenantsByLandlord(landlordId)
    }

    fun update(
        landlordId: UUID,
        id: UUID,
        request: TenantRequest
    ): Tenant {

        val tenant =
            tenantRepository.findTenantByLandlordAndId(landlordId, id)
                ?: throw RuntimeException("Tenant not found")

        val existing =
            tenantRepository.findByPhoneNumber(request.phoneNumber)

        if (existing != null && existing.id != id) {
            throw RuntimeException("Phone number already in use")
        }

        tenant.fullName = request.fullName
        tenant.phoneNumber = request.phoneNumber

        return tenantRepository.save(tenant)
    }

    fun delete(landlordId: UUID, id: UUID) {

        val tenant =
            tenantRepository.findTenantByLandlordAndId(landlordId, id)
                ?: throw RuntimeException("Tenant not found")

        tenant.isActive = false

        tenantRepository.save(tenant)
    }
}