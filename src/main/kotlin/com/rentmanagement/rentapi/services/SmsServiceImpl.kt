package com.rentmanagement.rentapi.services

import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service

@Service
class SmsServiceImpl : SmsService {

    private val log = LoggerFactory.getLogger(SmsServiceImpl::class.java)

    override fun sendSms(phone: String, message: String) {

        // 🔥 TEMP (console)
        log.info("📱 SMS → $phone → $message")
    }
}