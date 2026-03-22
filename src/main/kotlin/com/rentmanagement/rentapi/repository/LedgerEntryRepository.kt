package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.LedgerEntry
import com.rentmanagement.rentapi.models.LedgerCategory
import com.rentmanagement.rentapi.models.LedgerEntryType
import org.springframework.data.jpa.repository.JpaRepository
import org.springframework.data.jpa.repository.Query
import org.springframework.data.repository.query.Param
import java.math.BigDecimal
import java.util.UUID

interface LedgerEntryRepository : JpaRepository<LedgerEntry, UUID> {

    // =====================================================
    // 📒 WALLET TRANSACTIONS (ONLY REAL MONEY IN/OUT)
    // =====================================================
    @Query(
        """
        SELECT l
        FROM LedgerEntry l
        WHERE l.property.id = :propertyId
        AND (
            (l.entryType = :creditType AND l.category = :rentPayment)
            OR
            (l.entryType = :debitType AND l.category = :payout)
        )
        ORDER BY l.createdAt DESC
        """
    )
    fun findWalletTransactions(
        @Param("propertyId") propertyId: UUID,
        @Param("creditType") creditType: LedgerEntryType = LedgerEntryType.CREDIT,
        @Param("debitType") debitType: LedgerEntryType = LedgerEntryType.DEBIT,
        @Param("rentPayment") rentPayment: LedgerCategory = LedgerCategory.RENT_PAYMENT,
        @Param("payout") payout: LedgerCategory = LedgerCategory.PAYOUT
    ): List<LedgerEntry>

    // =====================================================
    // 💰 TOTAL COLLECTED (STRICT = ONLY RENT PAYMENTS)
    // =====================================================
    @Query(
        """
        SELECT COALESCE(SUM(l.amount), 0)
        FROM LedgerEntry l
        WHERE l.property.id = :propertyId
        AND l.entryType = :creditType
        AND l.category = :rentPayment
        """
    )
    fun getTotalCollected(
        @Param("propertyId") propertyId: UUID,
        @Param("creditType") creditType: LedgerEntryType = LedgerEntryType.CREDIT,
        @Param("rentPayment") rentPayment: LedgerCategory = LedgerCategory.RENT_PAYMENT
    ): BigDecimal

    // =====================================================
    // 📅 MONTHLY RENT CHARGED
    // =====================================================
    @Query(
        """
        SELECT COALESCE(SUM(l.amount), 0)
        FROM LedgerEntry l
        WHERE l.property.id = :propertyId
        AND l.entryType = :debitType
        AND l.category = :rentCharge
        AND EXTRACT(YEAR FROM l.createdAt) = :year
        AND EXTRACT(MONTH FROM l.createdAt) = :month
        """
    )
    fun sumRentChargesForMonth(
        @Param("propertyId") propertyId: UUID,
        @Param("year") year: Int,
        @Param("month") month: Int,
        @Param("debitType") debitType: LedgerEntryType = LedgerEntryType.DEBIT,
        @Param("rentCharge") rentCharge: LedgerCategory = LedgerCategory.RENT_CHARGE
    ): BigDecimal

    // =====================================================
    // 📅 MONTHLY PAYMENTS (ONLY REAL PAYMENTS)
    // =====================================================
    @Query(
        """
        SELECT COALESCE(SUM(l.amount), 0)
        FROM LedgerEntry l
        WHERE l.property.id = :propertyId
        AND l.entryType = :creditType
        AND l.category = :rentPayment
        AND EXTRACT(YEAR FROM l.createdAt) = :year
        AND EXTRACT(MONTH FROM l.createdAt) = :month
        """
    )
    fun sumPaymentsForMonth(
        @Param("propertyId") propertyId: UUID,
        @Param("year") year: Int,
        @Param("month") month: Int,
        @Param("creditType") creditType: LedgerEntryType = LedgerEntryType.CREDIT,
        @Param("rentPayment") rentPayment: LedgerCategory = LedgerCategory.RENT_PAYMENT
    ): BigDecimal
}