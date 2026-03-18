package com.rentmanagement.rentapi.repository

import com.rentmanagement.rentapi.models.User
import org.springframework.data.jpa.repository.JpaRepository
import java.util.UUID

interface UserRepository : JpaRepository<User, UUID> {

    fun findByEmail(email: String): User?

    fun findByPhone(phone: String): User?

    fun existsByEmail(email: String): Boolean

    fun existsByPhone(phone: String): Boolean // ✅ ADD (useful later)
}