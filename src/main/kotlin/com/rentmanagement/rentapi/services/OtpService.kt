package com.rentmanagement.rentapi.services

import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import java.time.LocalDateTime
import java.util.*

@Service
class OtpService(
    private val jdbcTemplate: JdbcTemplate,
    private val smsService: SmsService
) {

    // =========================
    // 📱 GENERATE OTP
    // =========================
    fun generateOtp(phone: String): String {

        val otp = (100000..999999).random().toString()
        val now = LocalDateTime.now()

        val existing = jdbcTemplate.queryForList(
            "SELECT * FROM otp_codes WHERE phone = ? ORDER BY created_at DESC LIMIT 1",
            phone
        )

        if (existing.isNotEmpty()) {
            val row = existing[0]

            val attempts = (row["attempts"] as Int)
            val lastSent = (row["last_sent_at"] as java.sql.Timestamp).toLocalDateTime()

            val waitSeconds = when (attempts) {
                0 -> 30
                1 -> 60
                2 -> 90
                else -> 3600
            }

            val nextAllowed = lastSent.plusSeconds(waitSeconds.toLong())

            if (now.isBefore(nextAllowed)) {
                throw RuntimeException("Wait before requesting another OTP")
            }

            jdbcTemplate.update(
                """
                UPDATE otp_codes
                SET code = ?, 
                    expires_at = ?, 
                    attempts = attempts + 1,
                    last_sent_at = ?
                WHERE phone = ?
                """,
                otp,
                now.plusMinutes(5),
                now,
                phone
            )

        } else {

            jdbcTemplate.update(
                """
                INSERT INTO otp_codes(phone, code, expires_at, attempts, last_sent_at)
                VALUES (?, ?, ?, 0, ?)
                """,
                phone,
                otp,
                now.plusMinutes(5),
                now
            )
        }

        smsService.sendSms(phone, "Your RentApp OTP is $otp")

        return otp
    }

    // =========================
    // 🔐 VERIFY OTP
    // =========================
    fun verifyOtp(phone: String, code: String): Boolean {

        val result = jdbcTemplate.queryForList(
            """
            SELECT * FROM otp_codes
            WHERE phone = ?
            ORDER BY created_at DESC LIMIT 1
            """,
            phone
        )

        if (result.isEmpty()) return false

        val row = result[0]

        val storedCode = row["code"].toString()
        val expiresAt = (row["expires_at"] as java.sql.Timestamp).toLocalDateTime()

        if (LocalDateTime.now().isAfter(expiresAt)) {
            return false
        }

        return storedCode == code
    }
}