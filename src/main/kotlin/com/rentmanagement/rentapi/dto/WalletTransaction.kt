package com.rentmanagement.rentapi.wallet.dto

import java.math.BigDecimal
import java.time.LocalDateTime
import java.util.UUID

data class WalletTransaction(

    val id: UUID,

    val amount: BigDecimal,

    val entryType: String,

    val category: String?,

    val reference: String?,

    val createdAt: LocalDateTime

)