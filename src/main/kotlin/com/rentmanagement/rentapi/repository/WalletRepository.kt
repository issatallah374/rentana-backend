package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.Wallet
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Lock
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import jakarta.persistence.LockModeType
import java.util.*

interface WalletRepository : JpaRepository<Wallet, UUID> {

    // =====================================================
    // 🔍 FIND BY PROPERTY (NORMAL)
    // =====================================================
    fun findByPropertyId(propertyId: UUID): Wallet?

    // =====================================================
    // 🔒 FIND WITH LOCK (🔥 USED IN PAYOUT SAFETY)
    // =====================================================
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT w FROM Wallet w WHERE w.property.id = :propertyId")
    fun findByPropertyIdForUpdate(
        @Param("propertyId") propertyId: UUID
    ): Wallet?

    // =====================================================
    // 🔍 FIND BY NATIONAL ID (PIN RESET)
    // =====================================================
    fun findByNationalId(nationalId: String): Wallet?
}