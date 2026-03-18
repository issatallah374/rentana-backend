package com.rentmanagement.rentapi.controller

import com.rentmanagement.rentapi.services.MpesaService
import org.springframework.web.bind.annotation.*

@RestController
@RequestMapping("/api/mpesa")
class MpesaCallbackController(
    private val mpesaService: MpesaService
) {

    @PostMapping("/callback")
    fun callback(
        @RequestBody payload: Map<String, Any>
    ): Map<String, String> {

        mpesaService.processCallback(payload)

        return mapOf(
            "ResultCode" to "0",
            "ResultDesc" to "Accepted"
        )
    }
}