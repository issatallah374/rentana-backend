package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.AuthRequest
import com.rentmanagement.rentapi.dto.AuthResponse
import com.rentmanagement.rentapi.dto.RegisterRequest
import com.rentmanagement.rentapi.models.User
import com.rentmanagement.rentapi.repository.UserRepository
import com.rentmanagement.rentapi.security.JwtUtil
import org.springframework.http.HttpStatus
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException
import org.springframework.security.crypto.password.PasswordEncoder

@RestController
@RequestMapping("/api/auth")
class AuthController(
    private val userRepository: UserRepository,
    private val passwordEncoder: PasswordEncoder,
    private val jwtUtil: JwtUtil
) {

    @PostMapping("/register")
    fun register(@RequestBody request: RegisterRequest): AuthResponse {

        if (userRepository.existsByEmail(request.email)) {
            throw ResponseStatusException(
                HttpStatus.CONFLICT,
                "User already exists"
            )
        }

        val user = User(
            fullName = request.fullName,
            email = request.email,
            passwordHash = passwordEncoder.encode(request.password),
            role = request.role,
            isActive = true
        )

        val savedUser = userRepository.save(user)

        val token = jwtUtil.generateToken(
            savedUser.id!!,     // ✅ FIXED
            savedUser.email,
            savedUser.role
        )

        return AuthResponse(token)
    }

    @PostMapping("/login")
    fun login(@RequestBody request: AuthRequest): AuthResponse {

        val user = userRepository.findByEmail(request.email)
            ?: throw ResponseStatusException(
                HttpStatus.UNAUTHORIZED,
                "Invalid email or password"
            )

        if (!user.isActive) {
            throw ResponseStatusException(
                HttpStatus.UNAUTHORIZED,
                "Account is disabled"
            )
        }

        val valid = passwordEncoder.matches(
            request.password,
            user.passwordHash
        )

        if (!valid) {
            throw ResponseStatusException(
                HttpStatus.UNAUTHORIZED,
                "Invalid email or password"
            )
        }

        val token = jwtUtil.generateToken(
            user.id!!,
            user.email,
            user.role
        )

        return AuthResponse(token)
    }
}