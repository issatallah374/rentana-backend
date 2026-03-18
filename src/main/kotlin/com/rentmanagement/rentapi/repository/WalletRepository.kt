package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Wallet
import com.rentmanagement.rentapi.models.Property
import org.springframework.data.jpa.repository.JpaRepository
import java.util.*

interface WalletRepository : JpaRepository<Wallet, UUID> {

    fun findByProperty(property: Property): Wallet?

}