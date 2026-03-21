package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import org.hibernate.annotations.JdbcTypeCode
import org.hibernate.type.SqlTypes
import java.time.LocalDateTime
import java.util.*
import java.math.BigDecimal

@Entity
@Table(name = "ledger_entries")
data class LedgerEntry(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "property_id", nullable = false)
    var property: Property? = null,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenancy_id")
    var tenancy: Tenancy? = null,

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "entry_type", columnDefinition = "ledger_entry_type", nullable = false)
    val entryType: LedgerEntryType,

    @Enumerated(EnumType.STRING)
    @JdbcTypeCode(SqlTypes.NAMED_ENUM)
    @Column(name = "category", columnDefinition = "ledger_category")
    val category: LedgerCategory? = null,

    @Column(nullable = false)
    val amount: BigDecimal,

    @Column(name = "reference")
    var reference: String? = null,

    @Column(name = "reference_id")
    val referenceId: UUID? = null,

    @Column(name = "created_at", nullable = false)
    val createdAt: LocalDateTime = LocalDateTime.now()
)