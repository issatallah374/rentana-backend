package com.rentmanagement.rentapi.services

import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets

@Service
class SmsServiceImpl(

    @Value("\${termii.apiKey:}") private val apiKey: String,
    @Value("\${termii.senderId:}") private val senderId: String // 🔥 optional

) : SmsService {

    private val log = LoggerFactory.getLogger(SmsServiceImpl::class.java)

    override fun sendSms(phone: String, message: String) {

        val formatted = formatPhone(phone)

        log.info("📤 Sending SMS → $formatted")

        // =========================
        // 🔥 DEV MODE
        // =========================
        if (apiKey.isBlank()) {
            log.warn("⚠️ No TERMII API KEY → DEV MODE")
            log.info("📱 SMS (DEV) → $formatted → $message")
            return
        }

        try {
            val url = URL("https://api.ng.termii.com/api/sms/send")

            // 🔥 BUILD JSON DYNAMICALLY
            val payload = if (senderId.isNotBlank()) {
                """
                {
                    "to": "$formatted",
                    "from": "$senderId",
                    "sms": "$message",
                    "type": "plain",
                    "channel": "generic",
                    "api_key": "$apiKey"
                }
                """.trimIndent()
            } else {
                """
                {
                    "to": "$formatted",
                    "sms": "$message",
                    "type": "plain",
                    "channel": "generic",
                    "api_key": "$apiKey"
                }
                """.trimIndent()
            }

            val conn = url.openConnection() as HttpURLConnection

            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.doOutput = true

            conn.outputStream.use {
                it.write(payload.toByteArray(StandardCharsets.UTF_8))
            }

            val response = try {
                conn.inputStream.bufferedReader().readText()
            } catch (e: Exception) {
                conn.errorStream?.bufferedReader()?.readText() ?: "No error response"
            }

            log.info("📱 TERMII RESPONSE → $response")

            // =========================
            // 🔥 AUTO FALLBACK IF SENDER FAILS
            // =========================
            if (response.contains("ApplicationSenderId not found") && senderId.isNotBlank()) {

                log.warn("⚠️ SenderId failed → retrying WITHOUT senderId")

                sendWithoutSender(formatted, message)
                return
            }

            if (response.contains("\"status\":\"error\"")) {
                log.error("❌ TERMII REJECTED SMS → $response")
            } else {
                log.info("✅ SMS SUCCESS → $formatted")
            }

        } catch (e: Exception) {
            log.error("❌ SMS FAILED → ${e.message}", e)
        }
    }

    // =========================
    // 🔁 FALLBACK METHOD
    // =========================
    private fun sendWithoutSender(phone: String, message: String) {

        try {
            val url = URL("https://api.ng.termii.com/api/sms/send")

            val payload = """
                {
                    "to": "$phone",
                    "sms": "$message",
                    "type": "plain",
                    "channel": "generic",
                    "api_key": "$apiKey"
                }
            """.trimIndent()

            val conn = url.openConnection() as HttpURLConnection

            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.doOutput = true

            conn.outputStream.use {
                it.write(payload.toByteArray(StandardCharsets.UTF_8))
            }

            val response = conn.inputStream.bufferedReader().readText()

            log.info("📱 FALLBACK SMS RESPONSE → $response")

        } catch (e: Exception) {
            log.error("❌ FALLBACK SMS FAILED → ${e.message}", e)
        }
    }

    // =========================
    // 📱 FORMAT PHONE (KENYA)
    // =========================
    private fun formatPhone(phone: String): String {
        return when {
            phone.startsWith("0") -> "254" + phone.substring(1)
            phone.startsWith("+254") -> "254" + phone.substring(4)
            phone.startsWith("254") -> phone
            else -> phone
        }
    }
}