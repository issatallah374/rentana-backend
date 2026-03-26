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
    @Value("\${termii.senderId:RentApp}") private val senderId: String

) : SmsService {

    private val log = LoggerFactory.getLogger(SmsServiceImpl::class.java)

    override fun sendSms(phone: String, message: String) {

        val formatted = formatPhone(phone)

        // 🔥 IF NO API KEY → DEV MODE
        if (apiKey.isBlank()) {
            log.info("📱 SMS (DEV MODE) → $formatted → $message")
            return
        }

        try {
            val url = URL("https://api.ng.termii.com/api/sms/send")

            val payload = """
                {
                    "to": "$formatted",
                    "from": "$senderId",
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

            log.info("📱 TERMII SMS SENT → $formatted → $response")

        } catch (e: Exception) {
            log.error("❌ TERMII SMS FAILED → ${e.message}")
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