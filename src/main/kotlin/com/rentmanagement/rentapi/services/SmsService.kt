package com.rentmanagement.rentapi.services

import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service

@Service
class SmsService {

    private val log = LoggerFactory.getLogger(SmsService::class.java)

    fun sendSms(phone: String, message: String) {
        log.info("📱 SMS → $phone → $message")

        // 🔥 Replace later with:
        // Africa's Talking / Twilio
    }
}