package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.StkRequest
import org.springframework.data.jpa.repository.JpaRepository
import java.util.*

interface StkRequestRepository : JpaRepository<StkRequest, UUID> {

    fun findByCheckoutRequestId(checkoutRequestId: String): StkRequest?
}