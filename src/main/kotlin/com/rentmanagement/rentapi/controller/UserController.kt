package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.UserResponse
import com.rentmanagement.rentapi.repository.UserRepository
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/users")
class UserController(
    private val userRepository: UserRepository
) {

    @GetMapping
    fun getAllUsers(): List<UserResponse> {
        return userRepository.findAll().map { user ->
            UserResponse(
                id = user.id!!,   // safe because DB-generated
                fullName = user.fullName,
                email = user.email,
                role = user.role,   // role is String in your entity
                isActive = user.isActive,
                createdAt = user.createdAt
            )
        }
    }
}
