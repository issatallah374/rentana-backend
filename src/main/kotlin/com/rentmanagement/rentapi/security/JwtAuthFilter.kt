package com.rentmanagement.rentapi.security

import jakarta.servlet.FilterChain
import jakarta.servlet.http.HttpServletRequest
import jakarta.servlet.http.HttpServletResponse
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken
import org.springframework.security.core.authority.SimpleGrantedAuthority
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource
import org.springframework.stereotype.Component
import org.springframework.web.filter.OncePerRequestFilter

@Component
class JwtAuthFilter(
    private val jwtUtil: JwtUtil
) : OncePerRequestFilter() {

    override fun shouldNotFilter(request: HttpServletRequest): Boolean {
        val path = request.servletPath

        return path.startsWith("/api/auth") ||
                path.startsWith("/error")
    }

    override fun doFilterInternal(
        request: HttpServletRequest,
        response: HttpServletResponse,
        filterChain: FilterChain
    ) {

        val authHeader = request.getHeader("Authorization")

        if (authHeader != null && authHeader.startsWith("Bearer ")) {

            val token = authHeader.substring(7)

            try {

                if (jwtUtil.validateToken(token)
                    && SecurityContextHolder.getContext().authentication == null) {

                    val userId = jwtUtil.extractUserId(token)
                    val role = jwtUtil.extractRole(token)

                    println("JWT AUTH SUCCESS → $userId ($role)")

                    val authorities = listOf(
                        SimpleGrantedAuthority("ROLE_$role")
                    )

                    val authToken = UsernamePasswordAuthenticationToken(
                        userId.toString(),   // ✅ principal is USER ID
                        null,
                        authorities
                    )

                    authToken.details =
                        WebAuthenticationDetailsSource()
                            .buildDetails(request)

                    SecurityContextHolder.getContext().authentication = authToken
                }

            } catch (e: Exception) {

                println("JWT AUTH FAILED → ${e.message}")
                SecurityContextHolder.clearContext()
            }
        }

        filterChain.doFilter(request, response)
    }
}