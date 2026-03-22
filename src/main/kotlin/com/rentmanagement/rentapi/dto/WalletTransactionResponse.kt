package com.rentmanagement.rentapi.wallet.dto

data class WalletTransactionResponse(

    val id: String,

    val amount: Double,

    val entryType: String,

    val category: String?,

    val reference: String?,

    val createdAt: String
)