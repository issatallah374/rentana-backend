package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.DashboardSnapshot
import com.rentmanagement.rentapi.repository.DashboardSnapshotRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.repository.PropertyRepository
import org.springframework.stereotype.Service
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.UUID

@Service
class DashboardSnapshotService(
    private val propertyRepository: PropertyRepository,
    private val ledgerRepository: LedgerEntryRepository,
    private val snapshotRepository: DashboardSnapshotRepository
) {

    fun createMonthlySnapshots() {

        val now = LocalDate.now()

        val year = now.year
        val month = now.monthValue

        val properties = propertyRepository.findAll()

        for (property in properties) {

            val propertyId: UUID = property.id!!

            // ✅ Check if snapshot already exists
            val existingSnapshot =
                snapshotRepository.findByPropertyIdAndYearAndMonth(
                    propertyId,
                    year,
                    month
                )

            if (existingSnapshot != null) {
                // Snapshot already exists → skip
                continue
            }

            val expected =
                ledgerRepository.sumRentChargesForMonth(
                    propertyId,
                    year,
                    month
                )

            val collected =
                ledgerRepository.sumPaymentsForMonth(
                    propertyId,
                    year,
                    month
                )

            val arrears = expected.subtract(collected)

            val snapshot = DashboardSnapshot(
                id = UUID.randomUUID(),
                propertyId = propertyId,
                year = year,
                month = month,
                rentExpected = expected,
                rentCollected = collected,
                arrears = arrears,
                createdAt = LocalDateTime.now()
            )

            snapshotRepository.save(snapshot)
        }
    }
}