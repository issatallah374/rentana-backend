package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.DashboardSnapshot
import com.rentmanagement.rentapi.repository.DashboardSnapshotRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.repository.PropertyRepository
import org.slf4j.LoggerFactory
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

    private val log = LoggerFactory.getLogger(DashboardSnapshotService::class.java)

    fun createMonthlySnapshots() {

        val now = LocalDate.now()
        val year = now.year
        val month = now.monthValue

        log.info("📊 Creating dashboard snapshots → $month/$year")

        val properties = propertyRepository.findAll()

        properties.forEach { property ->

            val propertyId: UUID = property.id!!

            // ✅ Skip if already exists
            val exists = snapshotRepository
                .findByPropertyIdAndYearAndMonth(propertyId, year, month)

            if (exists != null) {
                log.debug("⏭️ Snapshot exists → property=$propertyId")
                return@forEach
            }

            // ✅ Calculate values from ledger
            val expected = ledgerRepository
                .sumRentChargesForMonth(propertyId, year, month)

            val collected = ledgerRepository
                .sumPaymentsForMonth(propertyId, year, month)

            val arrears = expected.subtract(collected)

            val snapshot = DashboardSnapshot(
                propertyId = propertyId,
                year = year,
                month = month,
                rentExpected = expected,
                rentCollected = collected,
                arrears = arrears,
                createdAt = LocalDateTime.now()
            )

            snapshotRepository.save(snapshot)

            log.info("✅ Snapshot saved → property=$propertyId")
        }
    }
}