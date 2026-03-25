package com.rentmanagement.rentapi.dto

import java.util.UUID

data class SetWalletPinRequest(
    val propertyId: UUID,
    val pin: String,
    val nationalId: String,
    val phoneNumber: String
)