package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.PlatformTransaction
import org.springframework.data.jpa.repository.JpaRepository
import java.util.*

interface PlatformTransactionRepository : JpaRepository<PlatformTransaction, UUID> {

    fun existsByReference(reference: String): Boolean
}