package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.StkRequest
import com.rentmanagement.rentapi.repository.StkRequestRepository
import org.springframework.beans.factory.annotation.Value
import org.springframework.http.*
import org.springframework.stereotype.Service
import org.springframework.web.client.RestTemplate
import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.*
import java.util.Base64

@Service
class MpesaStkService(
    private val restTemplate: RestTemplate,
    private val stkRequestRepository: StkRequestRepository
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

    // =========================================================
    // 🔐 ACCESS TOKEN
    // =========================================================
    private fun getAccessToken(): String {

        val credentials = "$consumerKey:$consumerSecret"
        val encoded = Base64.getEncoder().encodeToString(credentials.toByteArray())

        val headers = HttpHeaders()
        headers.set("Authorization", "Basic $encoded")

        val request = HttpEntity<String>(headers)

        val response = restTemplate.exchange(
            "https://api.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials",
            HttpMethod.GET,
            request,
            Map::class.java
        )

        val body = response.body ?: throw RuntimeException("No token response")

        return body["access_token"]?.toString()
            ?: throw RuntimeException("Access token missing")
    }

    // =========================================================
    // 📞 PHONE NORMALIZATION (CRITICAL 🔥)
    // =========================================================
    private fun normalizePhone(phone: String): String {
        return when {
            phone.startsWith("0") -> "254" + phone.substring(1)
            phone.startsWith("+254") -> phone.substring(1)
            phone.startsWith("254") -> phone
            else -> throw RuntimeException("Invalid phone format")
        }
    }

    // =========================================================
    // 📲 STK PUSH (PRODUCTION READY)
    // =========================================================
    fun stkPush(
        phone: String,
        amount: BigDecimal,
        landlordId: UUID
    ): Any {

        try {

            val formattedPhone = normalizePhone(phone)

            val token = getAccessToken()

            val timestamp = SimpleDateFormat("yyyyMMddHHmmss").format(Date())

            val password = Base64.getEncoder().encodeToString(
                (shortcode + passkey + timestamp).toByteArray()
            )

            val accountRef = "SUB_${landlordId.toString().take(6)}"

            val headers = HttpHeaders()
            headers.contentType = MediaType.APPLICATION_JSON
            headers.setBearerAuth(token)

            val payload = mapOf(
                "BusinessShortCode" to shortcode,
                "Password" to password,
                "Timestamp" to timestamp,
                "TransactionType" to "CustomerPayBillOnline",
                "Amount" to amount.toInt(), // 🔥 FIXED
                "PartyA" to formattedPhone,
                "PartyB" to shortcode,
                "PhoneNumber" to formattedPhone,
                "CallBackURL" to callbackUrl,
                "AccountReference" to accountRef,
                "TransactionDesc" to "Rentana Subscription"
            )

            println("🔥 CALLBACK URL: $callbackUrl")
            println("📤 STK PAYLOAD: $payload")

            val request = HttpEntity(payload, headers)

            val response = restTemplate.postForEntity(
                "https://api.safaricom.co.ke/mpesa/stkpush/v1/processrequest",
                request,
                Map::class.java
            )

            val body = response.body ?: throw RuntimeException("No response from Safaricom")

            val checkoutId = body["CheckoutRequestID"]?.toString()
                ?: throw RuntimeException("Missing CheckoutRequestID")

            val merchantId = body["MerchantRequestID"]?.toString()

            // =====================================================
            // ✅ SAVE STK REQUEST
            // =====================================================
            stkRequestRepository.save(
                StkRequest(
                    checkoutRequestId = checkoutId,
                    merchantRequestId = merchantId,
                    landlordId = landlordId,
                    phoneNumber = formattedPhone,
                    amount = amount,
                    status = "PENDING"
                )
            )

            println("✅ STK SAVED → $checkoutId")

            return body

        } catch (e: Exception) {
            println("❌ STK ERROR: ${e.message}")
            throw e
        }
    }
}