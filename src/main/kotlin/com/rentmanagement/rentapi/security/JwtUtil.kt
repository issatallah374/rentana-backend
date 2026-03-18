package com.rentmanagement.rentapi.security

import io.jsonwebtoken.Claims
import io.jsonwebtoken.Jwts
import io.jsonwebtoken.SignatureAlgorithm
import io.jsonwebtoken.security.Keys
import org.springframework.stereotype.Component
import java.nio.charset.StandardCharsets
import java.util.*
import javax.crypto.SecretKey

@Component
class JwtUtil {

    private val secret =
        "my_super_secure_secret_key_12345678901234567890"

    private val secretKey: SecretKey =
        Keys.hmacShaKeyFor(secret.toByteArray(StandardCharsets.UTF_8))

    fun generateToken(userId: UUID, email: String, role: String): String {

        return Jwts.builder()
            .setSubject(userId.toString())   // ✅ store ID as subject
            .claim("email", email)
            .claim("role", role)
            .setIssuedAt(Date())
            .setExpiration(
                Date(System.currentTimeMillis() + 1000 * 60 * 60 * 24)
            )
            .signWith(secretKey, SignatureAlgorithm.HS256)
            .compact()
    }
    fun extractUserId(token: String): UUID =
        UUID.fromString(extractAllClaims(token).subject)

    fun extractEmail(token: String): String =
        extractAllClaims(token)["email"] as String

    fun extractRole(token: String): String =
        extractAllClaims(token)["role"] as String

    fun validateToken(token: String): Boolean =
        !isTokenExpired(token)

    private fun extractAllClaims(token: String): Claims =
        Jwts.parserBuilder()
            .setSigningKey(secretKey)
            .build()
            .parseClaimsJws(token)
            .body

    private fun isTokenExpired(token: String): Boolean =
        extractAllClaims(token).expiration.before(Date())
}
