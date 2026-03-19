package com.rentmanagement.rentapi.config

import org.springframework.beans.factory.annotation.Value
import org.springframework.context.annotation.Configuration

@Configuration
class MpesaConfig(

    @Value("\${mpesa.base-url}")
    val baseUrl: String,

    @Value("\${mpesa.consumer-key}")
    val consumerKey: String,

    @Value("\${mpesa.consumer-secret}")
    val consumerSecret: String,

    @Value("\${mpesa.shortcode}")
    val shortcode: String,

    @Value("\${mpesa.passkey}")
    val passkey: String,

    @Value("\${mpesa.callback-url}")
    val callbackUrl: String
)