package com.rentmanagement.rentapi.services

import com.fasterxml.jackson.databind.ObjectMapper
import com.rentmanagement.rentapi.repository.UnitRepository
import com.rentmanagement.rentapi.repository.TenancyRepository
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service
import org.slf4j.LoggerFactory

@Service
class MpesaService(
    private val unitRepository: UnitRepository,
    private val tenancyRepository: TenancyRepository,
    private val jdbcTemplate: JdbcTemplate
) {

    private val log = LoggerFactory.getLogger(MpesaService::class.java)
    private val objectMapper = ObjectMapper()

    fun processCallback(payload: Map<String, Any>) {

        try {

            val body = payload["Body"] as? Map<*, *> ?: return
            val callback = body["stkCallback"] as? Map<*, *> ?: return
            val metadata = callback["CallbackMetadata"] as? Map<*, *> ?: return
            val items = metadata["Item"] as? List<Map<String, Any>> ?: return

            var amount: Double? = null
            var reference: String? = null
            var phone: String? = null
            var account: String? = null

            for (item in items) {

                when (item["Name"]) {

                    "Amount" ->
                        amount = (item["Value"] as Number).toDouble()

                    "MpesaReceiptNumber" ->
                        reference = item["Value"].toString()

                    "PhoneNumber" ->
                        phone = item["Value"].toString()

                    "AccountReference" ->
                        account = item["Value"].toString()
                }
            }

            if (reference == null || amount == null || account == null) {
                log.warn("Mpesa callback missing fields")
                return
            }

            log.info("Mpesa payment received: ref=$reference amount=$amount account=$account")

            val jsonPayload = objectMapper.writeValueAsString(payload)

            jdbcTemplate.update(
                """
                INSERT INTO mpesa_transactions(
                    transaction_code,
                    phone_number,
                    account_reference,
                    amount,
                    raw_payload
                )
                VALUES (?, ?, ?, ?, ?::jsonb)
                ON CONFLICT (transaction_code) DO NOTHING
                """,
                reference,
                phone,
                account,
                amount,
                jsonPayload
            )

            val unit = unitRepository.findByReferenceNumber(account)

            if (unit == null) {
                log.warn("Unit not found for account: $account")
                return
            }

            val tenancy = tenancyRepository
                .findByUnitIdAndIsActiveTrue(unit.id!!)

            if (tenancy == null) {
                log.warn("No active tenancy for unit: ${unit.id}")
                return
            }

            log.info("Tenancy found: ${tenancy.id}")

            jdbcTemplate.execute(
                "SELECT process_payment(?::uuid, ?::numeric, ?)",
                { ps ->
                    ps.setObject(1, tenancy.id)
                    ps.setDouble(2, amount!!)
                    ps.setString(3, reference)
                    ps.execute()
                }
            )

            log.info("Payment processed successfully")

        } catch (e: Exception) {

            log.error("Mpesa callback processing failed", e)

        }
    }
}