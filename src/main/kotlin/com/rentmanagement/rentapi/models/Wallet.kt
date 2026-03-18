package com.rentmanagement.rentapi.models

import jakarta.persistence.*
import java.math.BigDecimal
import java.util.UUID

@Entity
@Table(name = "wallets")
class Wallet(

    @Id
    @GeneratedValue
    val id: UUID? = null,

    @ManyToOne
    val landlord: User,

    @OneToOne
    val property: Property,

    var balance: BigDecimal = BigDecimal.ZERO,

    var autoPayoutEnabled: Boolean = false,

    var adminApprovalEnabled: Boolean = true

)