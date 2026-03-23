package com.rentmanagement.rentapi.config

import com.rentmanagement.rentapi.security.SubscriptionInterceptor
import org.springframework.context.annotation.Configuration
import org.springframework.web.servlet.config.annotation.InterceptorRegistry
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer

@Configuration
class WebConfig(
    private val subscriptionInterceptor: SubscriptionInterceptor
) : WebMvcConfigurer {

    override fun addInterceptors(registry: InterceptorRegistry) {
        registry.addInterceptor(subscriptionInterceptor)
            .excludePathPatterns(
                "/api/mpesa/**",     // ✅ CRITICAL FIX
                "/api/auth/**",
                "/error"
            )
    }
}