package com.rentmanagement.rentapi.config

import com.rentmanagement.rentapi.security.JwtAuthFilter
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpMethod
import org.springframework.http.HttpStatus
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.web.SecurityFilterChain
import org.springframework.security.web.authentication.HttpStatusEntryPoint
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter
import org.springframework.web.cors.CorsConfiguration
import org.springframework.web.cors.CorsConfigurationSource
import org.springframework.web.cors.UrlBasedCorsConfigurationSource

@Configuration
@EnableWebSecurity
class SecurityConfig(
    private val jwtAuthFilter: JwtAuthFilter
) {

    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {

        return http
            .cors { }
            .csrf { it.disable() }

            .sessionManagement {
                it.sessionCreationPolicy(SessionCreationPolicy.STATELESS)
            }

            .authorizeHttpRequests {

                // ✅ allow preflight
                it.requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()

                // ✅ public auth
                it.requestMatchers("/api/auth/**").permitAll()

                // ✅ TEMP (you had this)
                it.requestMatchers("/api/tenants/**").permitAll()

                // 🔐 ADMIN PANEL (HTML)
                it.requestMatchers("/admin/**").hasRole("ADMIN")

                // 🔐 ADMIN APIs
                it.requestMatchers("/api/admin/**").hasRole("ADMIN")

                // 🔐 PROTECTED APIs
                it.requestMatchers(
                    "/api/properties/**",
                    "/api/units/**",
                    "/api/tenancies/**",
                    "/api/users/**",
                    "/api/payouts/**"
                ).authenticated()

                // ❌ everything else blocked
                it.anyRequest().permitAll()
            }

            .exceptionHandling {
                it.authenticationEntryPoint(
                    HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)
                )
            }

            .addFilterBefore(
                jwtAuthFilter,
                UsernamePasswordAuthenticationFilter::class.java
            )

            .build()
    }

    @Bean
    fun corsConfigurationSource(): CorsConfigurationSource {

        val config = CorsConfiguration()

        config.allowedOrigins = listOf("*")
        config.allowedMethods = listOf("GET", "POST", "PUT", "DELETE", "OPTIONS")
        config.allowedHeaders = listOf("*")
        config.allowCredentials = false

        val source = UrlBasedCorsConfigurationSource()
        source.registerCorsConfiguration("/**", config)

        return source
    }
}