package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Wallet
import org.springframework.data.jpa.repository.JpaRepository
import java.util.*

interface WalletRepository : JpaRepository<Wallet, UUID> {

    // ✅ FIXED (NO ENTITY MATCHING BUGS)
    fun findByPropertyId(propertyId: UUID): Wallet?




    fun findByNationalId(nationalId: String): Wallet?
}