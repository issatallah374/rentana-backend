package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.DashboardSnapshot
import com.rentmanagement.rentapi.repository.DashboardSnapshotRepository
import com.rentmanagement.rentapi.repository.LedgerEntryRepository
import com.rentmanagement.rentapi.repository.PropertyRepository
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.UUID

@Service
class DashboardSnapshotService(
    private val propertyRepository: PropertyRepository,
    private val ledgerRepository: LedgerEntryRepository,
    private val snapshotRepository: DashboardSnapshotRepository
) {

    private val log =
        LoggerFactory.getLogger(
            DashboardSnapshotService::class.java
        )

    // =====================================================
    // 📊 CREATE MONTHLY SNAPSHOTS
    // =====================================================

    fun createMonthlySnapshots() {

        val now = LocalDate.now()

        val year = now.year
        val month = now.monthValue

        log.info(
            "📊 Creating dashboard snapshots → $month/$year"
        )

        val properties =
            propertyRepository.findAll()

        properties.forEach { property ->

            val propertyId: UUID =
                property.id!!

            // =====================================================
            // ✅ SKIP IF ALREADY EXISTS
            // =====================================================

            val exists =
                snapshotRepository
                    .findByPropertyIdAndYearAndMonth(
                        propertyId,
                        year,
                        month
                    )

            if (exists != null) {

                log.debug(
                    "⏭️ Snapshot already exists → property=$propertyId"
                )

                return@forEach
            }

            // =====================================================
            // 💰 EXPECTED RENT
            // =====================================================

            val expected =
                ledgerRepository
                    .sumRentChargesForMonth(
                        propertyId,
                        year,
                        month
                    ) ?: BigDecimal.ZERO

            // =====================================================
            // 💵 COLLECTED RENT
            // =====================================================

            val collected =
                ledgerRepository
                    .sumPaymentsForMonth(
                        propertyId,
                        year,
                        month
                    ) ?: BigDecimal.ZERO

            // =====================================================
            // ⚠️ ARREARS
            // =====================================================

            val arrears =
                expected.subtract(collected)

            // =====================================================
            // 💾 CREATE SNAPSHOT
            // =====================================================

            val snapshot =
                DashboardSnapshot(
                    propertyId = propertyId,
                    year = year,
                    month = month,
                    rentExpected = expected,
                    rentCollected = collected,
                    arrears = arrears,
                    createdAt = LocalDateTime.now()
                )

            snapshotRepository.save(snapshot)

            log.info(
                """
                ✅ Snapshot saved
                → property=$propertyId
                → expected=$expected
                → collected=$collected
                → arrears=$arrears
                """.trimIndent()
            )
        }

        log.info(
            "✅ Monthly snapshot creation complete"
        )
    }
}