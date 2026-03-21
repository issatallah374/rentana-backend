package com.rentmanagement.rentapi.wallet.dto

data class WalletResponse(

    val balance: Double,

    val totalCollected: Double,

    val payoutSetupComplete: Boolean,

    // 🔥 ADD THESE (THIS FIXES EVERYTHING)
    val mpesaPhone: String?,

    val accountNumber: String?,

    val bankName: String?
)