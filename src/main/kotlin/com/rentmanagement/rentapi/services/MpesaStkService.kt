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

    // ✅ NEW (ENV SWITCH)
    @Value("\${mpesa.baseUrl}")
    lateinit var baseUrl: String

    // =========================================================
    // 🔐 ACCESS TOKEN
    // =========================================================
    private fun getAccessToken(): String {

        val credentials = "$consumerKey:$consumerSecret"
        val encoded = Base64.getEncoder().encodeToString(credentials.toByteArray())

        val headers = HttpHeaders().apply {
            set("Authorization", "Basic $encoded")
        }

        val request = HttpEntity<String>(headers)

        val response = restTemplate.exchange(
            "$baseUrl/oauth/v1/generate?grant_type=client_credentials",
            HttpMethod.GET,
            request,
            Map::class.java
        )

        val body = response.body ?: throw RuntimeException("No token response")

        val token = body["access_token"]?.toString()
            ?: throw RuntimeException("Access token missing")

        log.info("🔐 Access token acquired")

        return token
    }

    // =========================================================
    // 📞 PHONE NORMALIZATION
    // =========================================================
    private fun normalizePhone(phone: String): String {
        return when {
            phone.startsWith("0") -> "254" + phone.substring(1)
            phone.startsWith("+254") -> phone.substring(1)
            phone.startsWith("254") -> phone
            else -> throw RuntimeException("Invalid phone format: $phone")
        }
    }

    // =========================================================
    // 📲 STK PUSH (WITH PLAN ID)
    // =========================================================
    fun stkPush(
        phone: String,
        amount: BigDecimal,
        landlordId: UUID,
        planId: UUID
    ): Map<String, Any> {

        try {

            // 🔐 Validate callback URL
            if (!callbackUrl.startsWith("https://")) {
                throw RuntimeException("Callback URL must be HTTPS")
            }

            val formattedPhone = normalizePhone(phone)
            val token = getAccessToken()
            val timestamp = SimpleDateFormat("yyyyMMddHHmmss").format(Date())

            val password = Base64.getEncoder().encodeToString(
                (shortcode + passkey + timestamp).toByteArray()
            )

            val accountRef = "SUB_${landlordId.toString().take(6)}"

            val headers = HttpHeaders().apply {
                contentType = MediaType.APPLICATION_JSON
                setBearerAuth(token)
            }

            val payload = mapOf(
                "BusinessShortCode" to shortcode,
                "Password" to password,
                "Timestamp" to timestamp,
                "TransactionType" to "CustomerPayBillOnline",
                "Amount" to amount.setScale(0).toInt(), // ✅ SAFE
                "PartyA" to formattedPhone,
                "PartyB" to shortcode,
                "PhoneNumber" to formattedPhone,
                "CallBackURL" to callbackUrl,
                "AccountReference" to accountRef,
                "TransactionDesc" to "Subscription Payment"
            )

            log.info("📤 STK REQUEST → phone=$formattedPhone amount=$amount plan=$planId")

            val request = HttpEntity(payload, headers)

            val response = restTemplate.postForEntity(
                "$baseUrl/mpesa/stkpush/v1/processrequest",
                request,
                Map::class.java
            )

            val body = response.body ?: throw RuntimeException("No response from Safaricom")

            log.info("📥 STK RESPONSE → $body")

            val checkoutId = body["CheckoutRequestID"]?.toString()
                ?: throw RuntimeException("Missing CheckoutRequestID")

            val merchantId = body["MerchantRequestID"]?.toString()

            // =====================================================
            // ⚠️ IDEMPOTENCY CHECK
            // =====================================================
            if (stkRequestRepository.findByCheckoutRequestId(checkoutId) != null) {
                log.warn("⚠️ Duplicate STK request → $checkoutId")
                return body as Map<String, Any>
            }

            // =====================================================
            // 💾 SAVE STK REQUEST WITH PLAN ID
            // =====================================================
            stkRequestRepository.save(
                StkRequest(
                    checkoutRequestId = checkoutId,
                    merchantRequestId = merchantId,
                    landlordId = landlordId,
                    planId = planId,
                    phoneNumber = formattedPhone,
                    amount = amount,
                    status = "PENDING"
                )
            )

            log.info("✅ STK SAVED → checkoutId=$checkoutId planId=$planId")

            return body as Map<String, Any>

        } catch (e: Exception) {
            log.error("❌ STK ERROR → ${e.message}", e)
            throw e
        }
    }
}