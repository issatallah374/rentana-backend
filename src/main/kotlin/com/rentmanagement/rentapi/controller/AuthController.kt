package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.dto.*
import com.rentmanagement.rentapi.models.User
import com.rentmanagement.rentapi.repository.UserRepository
import com.rentmanagement.rentapi.security.JwtUtil
import com.rentmanagement.rentapi.services.OtpService
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.*
import org.springframework.web.server.ResponseStatusException
import org.springframework.security.crypto.password.PasswordEncoder

@RestController
@RequestMapping("/api/auth")
class AuthController(
    private val userRepository: UserRepository,
    private val passwordEncoder: PasswordEncoder,
    private val jwtUtil: JwtUtil,
    private val otpService: OtpService
) {

    // =========================
    // 🔧 PHONE NORMALIZATION
    // =========================
    private fun normalizePhone(phone: String): String {
        return when {
            phone.startsWith("254") -> "0" + phone.substring(3)
            phone.startsWith("+254") -> "0" + phone.substring(4)
            else -> phone
        }
    }

    // =========================
    // 🟢 REGISTER
    // =========================
    @PostMapping("/register")
    fun register(@RequestBody request: RegisterRequest): AuthResponse {

        if (userRepository.existsByEmail(request.email)) {
            throw ResponseStatusException(HttpStatus.CONFLICT, "User already exists")
        }

        val phone = normalizePhone(request.phone)

        if (userRepository.existsByPhone(phone)) {
            throw ResponseStatusException(HttpStatus.CONFLICT, "Phone already in use")
        }

        val user = User(
            fullName = request.fullName,
            email = request.email,
            phone = phone,
            passwordHash = passwordEncoder.encode(request.password),
            role = request.role,
            isActive = true
        )

        val savedUser = userRepository.save(user)

        val token = jwtUtil.generateToken(
            savedUser.id!!,
            savedUser.email,
            savedUser.role
        )

        return AuthResponse(token)
    }

    // =========================
    // 🔵 LOGIN (EMAIL)
    // =========================
    @PostMapping("/login")
    fun login(@RequestBody request: AuthRequest): AuthResponse {

        val user = userRepository.findByEmail(request.email)
            ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid email or password")

        if (!user.isActive) {
            throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "Account disabled")
        }

        val valid = passwordEncoder.matches(request.password, user.passwordHash)

        if (!valid) {
            throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid email or password")
        }

        val token = jwtUtil.generateToken(
            user.id!!,
            user.email,
            user.role
        )

        return AuthResponse(token)
    }

    // =====================================================
    // 🔐 LOGIN WITH PIN
    // =====================================================
    @PostMapping("/pin-login")
    fun loginWithPin(@RequestBody request: PinLoginRequest): AuthResponse {

        val phone = normalizePhone(request.phone)

        val user = userRepository.findByPhone(phone)
            ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "User not found")

        if (!user.isActive) {
            throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "Account disabled")
        }

        if (user.pinHash.isNullOrBlank()) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "PIN not set")
        }

        val valid = passwordEncoder.matches(request.pin, user.pinHash)

        if (!valid) {
            throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "Invalid PIN")
        }

        val token = jwtUtil.generateToken(
            user.id!!,
            user.email,
            user.role
        )

        return AuthResponse(token)
    }

    // =====================================================
    // 📱 SEND OTP (WITH RATE LIMIT FROM SERVICE)
    // =====================================================
    @PostMapping("/send-otp")
    fun sendOtp(@RequestParam phone: String): ResponseEntity<String> {

        val normalizedPhone = normalizePhone(phone)

        otpService.generateOtp(normalizedPhone)

        return ResponseEntity.ok("OTP sent successfully")
    }

    // =====================================================
    // 🔐 VERIFY OTP (OPTIONAL ENDPOINT)
    // =====================================================
    @PostMapping("/verify-otp")
    fun verifyOtp(@RequestBody request: VerifyOtpRequest): ResponseEntity<String> {

        val phone = normalizePhone(request.phone)

        val valid = otpService.verifyOtp(phone, request.otp)

        if (!valid) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid or expired OTP")
        }

        return ResponseEntity.ok("OTP verified")
    }

    // =====================================================
    // 🔐 SET USER PIN (WITH OTP VALIDATION)
    // =====================================================
    @PostMapping("/set-pin")
    fun setPin(@RequestBody request: SetUserPinRequest): ResponseEntity<String> {

        val phone = normalizePhone(request.phone)

        val user = userRepository.findByPhone(phone)
            ?: throw ResponseStatusException(HttpStatus.NOT_FOUND, "User not found")

        if (request.pin.length < 4) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "PIN must be at least 4 digits")
        }

        // 🔥 VERIFY OTP
        val validOtp = otpService.verifyOtp(phone, request.otp)

        if (!validOtp) {
            throw ResponseStatusException(HttpStatus.BAD_REQUEST, "Invalid or expired OTP")
        }

        user.pinHash = passwordEncoder.encode(request.pin)

        userRepository.save(user)

        return ResponseEntity.ok("PIN set successfully")
    }
}