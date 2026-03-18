package com.rentmanagement.rentapi.dto

import java.util.UUID

data class TenantResponse(

    val id: UUID,

    val fullName: String,

    val phoneNumber: String,

    val isActive: Boolean

)