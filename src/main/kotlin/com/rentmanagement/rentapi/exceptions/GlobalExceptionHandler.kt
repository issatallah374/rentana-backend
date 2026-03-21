package com.rentmanagement.rentapi.exceptions

import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice

data class ErrorResponse(
    val message: String
)

@RestControllerAdvice
class GlobalExceptionHandler {

    private val log = LoggerFactory.getLogger(GlobalExceptionHandler::class.java)

    // =====================================================
    // ✅ BUSINESS ERRORS (YOUR CUSTOM)
    // =====================================================
    @ExceptionHandler(BadRequestException::class)
    fun handleBadRequest(ex: BadRequestException): ResponseEntity<ErrorResponse> {

        log.warn("⚠️ Bad request: ${ex.message}")

        return ResponseEntity
            .status(HttpStatus.BAD_REQUEST)
            .body(ErrorResponse(ex.message ?: "Bad request"))
    }

    // =====================================================
    // ✅ VALIDATION ERRORS (DTO @Valid)
    // =====================================================
    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(ex: MethodArgumentNotValidException): ResponseEntity<ErrorResponse> {

        val message = ex.bindingResult
            .fieldErrors
            .firstOrNull()
            ?.defaultMessage ?: "Invalid request"

        log.warn("⚠️ Validation error: $message")

        return ResponseEntity
            .status(HttpStatus.BAD_REQUEST)
            .body(ErrorResponse(message))
    }

    // =====================================================
    // ❌ UNKNOWN ERRORS
    // =====================================================
    @ExceptionHandler(Exception::class)
    fun handleGeneric(ex: Exception): ResponseEntity<ErrorResponse> {

        log.error("❌ Internal error", ex)

        return ResponseEntity
            .status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(ErrorResponse("Something went wrong"))
    }
}