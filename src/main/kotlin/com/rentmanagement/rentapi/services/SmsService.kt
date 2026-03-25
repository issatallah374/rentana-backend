package com.rentmanagement.rentapi.services

interface SmsService {
    fun sendSms(phone: String, message: String)
}