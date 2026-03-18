package com.rentmanagement.rentapi.services

import org.springframework.beans.factory.annotation.Value
import org.springframework.http.*
import org.springframework.stereotype.Service
import org.springframework.web.client.RestTemplate
import java.text.SimpleDateFormat
import java.util.*
import java.util.Base64

@Service
class MpesaStkService(
    private val restTemplate: RestTemplate
) {

    @Value("\${mpesa.consumerKey}")
    lateinit var consumerKey: String

    @Value("\${mpesa.consumerSecret}")
    lateinit var consumerSecret: String

    @Value("\${mpesa.shortcode}")
    lateinit var shortcode: String

    @Value("\${mpesa.passkey}")
    lateinit var passkey: String

    @Value("\${mpesa.callbackUrl}")
    lateinit var callbackUrl: String

    private fun getAccessToken(): String {
        val credentials = "$consumerKey:$consumerSecret"
        val encoded = Base64.getEncoder().encodeToString(credentials.toByteArray())

        val headers = HttpHeaders()
        headers.set("Authorization", "Basic $encoded")

        val request = HttpEntity<String>(headers)

        val response = restTemplate.exchange(
            "https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials",
            HttpMethod.GET,
            request,
            Map::class.java
        )

        return response.body?.get("access_token").toString()
    }

    fun stkPush(phone: String, amount: String, accountRef: String): Any {

        val token = getAccessToken()

        val timestamp = SimpleDateFormat("yyyyMMddHHmmss").format(Date())
        val password = Base64.getEncoder().encodeToString(
            (shortcode + passkey + timestamp).toByteArray()
        )

        val headers = HttpHeaders()
        headers.contentType = MediaType.APPLICATION_JSON
        headers.setBearerAuth(token)

        val payload = mapOf(
            "BusinessShortCode" to shortcode,
            "Password" to password,
            "Timestamp" to timestamp,
            "TransactionType" to "CustomerPayBillOnline",
            "Amount" to amount,
            "PartyA" to phone,
            "PartyB" to shortcode,
            "PhoneNumber" to phone,
            "CallBackURL" to callbackUrl,
            "AccountReference" to accountRef,
            "TransactionDesc" to "Rentana Subscription"
        )

        val request = HttpEntity(payload, headers)

        val response = restTemplate.postForEntity(
            "https://sandbox.safaricom.co.ke/mpesa/stkpush/v1/processrequest",
            request,
            Any::class.java
        )

        return response.body!!
    }
}