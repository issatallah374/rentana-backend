package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.time.LocalDateTime
import java.util.*
import java.math.BigDecimal


@Entity
@Table(name = "payments")
data class Payment(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "tenancy_id", nullable = false)
    val tenancy: Tenancy,

    @Column(nullable = false)
    val amount: BigDecimal,

    @Column(name = "payment_method", nullable = false)
    val paymentMethod: String,

    @Column(name = "transaction_code")
    val transactionCode: String? = null,

    @Column(name = "receipt_number")
    val receiptNumber: String? = null,

    @Column(name = "receipt_url")
    val receiptUrl: String? = null,

    @Column(name = "payment_date", nullable = false)
    val paymentDate: LocalDateTime,

    @Column(name = "status")
    val status: String = "SUCCESS", // or PENDING / FAILED

    @Column(name = "processed_at")
    val processedAt: LocalDateTime = LocalDateTime.now(),

    @Column(name = "created_at")
    val createdAt: LocalDateTime = LocalDateTime.now()


)