package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.LedgerEntry
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.math.BigDecimal
import java.util.UUID

interface LedgerEntryRepository : JpaRepository<LedgerEntry, UUID> {

    // ===============================
    // 📒 WALLET TRANSACTIONS
    // ===============================
    @Query(
        """
        SELECT l
        FROM LedgerEntry l
        WHERE l.property.id = :propertyId
        ORDER BY l.createdAt DESC
        """
    )
    fun findWalletTransactions(
        @Param("propertyId") propertyId: UUID
    ): List<LedgerEntry>

    // ===============================
    // 💰 TOTAL COLLECTED (ALL TIME)
    // ===============================
    @Query(
        """
        SELECT COALESCE(SUM(l.amount),0)
        FROM LedgerEntry l
        WHERE l.property.id = :propertyId
        AND l.entryType = 'CREDIT'
        """
    )
    fun getTotalCollected(
        @Param("propertyId") propertyId: UUID
    ): BigDecimal

    // ===============================
    // 📅 MONTHLY RENT CHARGED
    // ===============================
    @Query(
        """
        SELECT COALESCE(SUM(l.amount),0)
        FROM LedgerEntry l
        WHERE l.property.id = :propertyId
        AND l.entryType = 'DEBIT'
        AND EXTRACT(YEAR FROM l.createdAt) = :year
        AND EXTRACT(MONTH FROM l.createdAt) = :month
        """
    )
    fun sumRentChargesForMonth(
        @Param("propertyId") propertyId: UUID,
        @Param("year") year: Int,
        @Param("month") month: Int
    ): BigDecimal

    // ===============================
    // 📅 MONTHLY PAYMENTS
    // ===============================
    @Query(
        """
        SELECT COALESCE(SUM(l.amount),0)
        FROM LedgerEntry l
        WHERE l.property.id = :propertyId
        AND l.entryType = 'CREDIT'
        AND EXTRACT(YEAR FROM l.createdAt) = :year
        AND EXTRACT(MONTH FROM l.createdAt) = :month
        """
    )
    fun sumPaymentsForMonth(
        @Param("propertyId") propertyId: UUID,
        @Param("year") year: Int,
        @Param("month") month: Int
    ): BigDecimal
}