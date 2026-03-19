package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.math.BigDecimal
import java.time.LocalDateTime
import java.util.UUID

@Entity
@Table(name = "stk_requests")
data class StkRequest(

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    var id: UUID? = null,

    @Column(name = "checkout_request_id", nullable = false, unique = true)
    var checkoutRequestId: String,

    @Column(name = "merchant_request_id")
    var merchantRequestId: String? = null,

    @Column(name = "landlord_id", nullable = false)
    var landlordId: UUID,

    @Column(name = "phone_number")
    var phoneNumber: String? = null,

    @Column(nullable = false)
    var amount: BigDecimal,

    @Column(nullable = false)
    var status: String = "PENDING",

    @Column(name = "created_at")
    var createdAt: LocalDateTime = LocalDateTime.now()
)