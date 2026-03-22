package com.rentmanagement.rentapi.services

import com.rentmanagement.rentapi.models.StkRequest
import com.rentmanagement.rentapi.repository.StkRequestRepository
import org.slf4j.LoggerFactory
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

    private val log = LoggerFactory.getLogger(MpesaStkService::class.java)

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

        return try {

            log.info("🔐 Requesting M-Pesa access token...")

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

            log.info("📥 TOKEN RESPONSE → ${response.body}")

            val token = response.body?.get("access_token")?.toString()
                ?: throw RuntimeException("Access token missing")

            log.info("✅ Access token acquired")

            token

        } catch (e: Exception) {
            log.error("❌ TOKEN REQUEST FAILED", e)
            throw e
        }
    }

    // =========================================================
    // 📞 PHONE NORMALIZATION
    // =========================================================
    private fun normalizePhone(phone: String): String {
        val normalized = when {
            phone.startsWith("0") -> "254" + phone.substring(1)
            phone.startsWith("+254") -> phone.substring(1)
            phone.startsWith("254") -> phone
            else -> throw RuntimeException("Invalid phone format")
        }

        log.info("📱 Phone normalized → $phone → $normalized")

        return normalized
    }

    // =========================================================
    // 📲 STK PUSH (FULL DEBUG)
    // =========================================================
    fun stkPush(
        phone: String,
        amount: BigDecimal,
        landlordId: UUID
    ): Any {

        try {

            log.info("🚀 ===== STK PUSH START =====")
            log.info("📌 Input → phone=$phone amount=$amount landlord=$landlordId")

            val formattedPhone = normalizePhone(phone)
            val token = getAccessToken()

            val timestamp = SimpleDateFormat("yyyyMMddHHmmss").format(Date())

            val password = Base64.getEncoder().encodeToString(
                (shortcode + passkey + timestamp).toByteArray()
            )

            val accountRef = "SUB_${landlordId.toString().take(6)}"

            val payload = mapOf(
                "BusinessShortCode" to shortcode,
                "Password" to password,
                "Timestamp" to timestamp,
                "TransactionType" to "CustomerPayBillOnline",
                "Amount" to amount.toInt(),
                "PartyA" to formattedPhone,
                "PartyB" to shortcode,
                "PhoneNumber" to formattedPhone,
                "CallBackURL" to callbackUrl,
                "AccountReference" to accountRef,
                "TransactionDesc" to "Rentana Subscription"
            )

            log.info("📤 STK REQUEST → $payload")
            log.info("🌐 CALLBACK URL → $callbackUrl")

            val headers = HttpHeaders()
            headers.contentType = MediaType.APPLICATION_JSON
            headers.setBearerAuth(token)

            val request = HttpEntity(payload, headers)

            val response = restTemplate.postForEntity(
                "https://api.safaricom.co.ke/mpesa/stkpush/v1/processrequest",
                request,
                Map::class.java
            )

            log.info("📥 STK RESPONSE → ${response.body}")

            val body = response.body ?: throw RuntimeException("No response")

            val checkoutId = body["CheckoutRequestID"]?.toString()
                ?: throw RuntimeException("Missing CheckoutRequestID")

            val merchantId = body["MerchantRequestID"]?.toString()

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

            log.info("✅ STK SAVED → checkoutId=$checkoutId")

            return body

        } catch (e: Exception) {
            log.error("❌ STK PUSH FAILED", e)
            throw e
        }
    }
}