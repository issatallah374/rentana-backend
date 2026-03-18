package com.rentmanagement.rentapi.mapper

import com.rentmanagement.rentapi.dto.PropertyResponse
import com.rentmanagement.rentapi.models.Property

object PropertyMapper {

    fun toResponse(property: Property): PropertyResponse {
        return PropertyResponse(
            id = property.id!!,
            name = property.name,
            address = property.address,
            city = property.city,
            country = property.country,
            createdAt = property.createdAt
        )
    }

}
