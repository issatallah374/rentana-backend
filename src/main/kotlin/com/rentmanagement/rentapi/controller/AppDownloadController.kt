package com.rentmanagement.rentapi.controller

import org.springframework.beans.factory.annotation.Value
import org.springframework.core.io.ClassPathResource
import org.springframework.core.io.FileSystemResource
import org.springframework.core.io.Resource
import org.springframework.http.HttpHeaders
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController

@RestController
class AppDownloadController(
    @Value("\${rentana.apk-url:}") private val apkUrl: String,
    @Value("\${rentana.apk-file:}") private val apkFile: String
) {

    @GetMapping("/download", "/download/app", "/app")
    fun downloadSection(): ResponseEntity<Void> {
        return ResponseEntity.status(HttpStatus.FOUND)
            .header(HttpHeaders.LOCATION, "/#download")
            .build()
    }

    @GetMapping("/download/rentana.apk")
    fun downloadApk(): ResponseEntity<Resource> {

        if (apkUrl.isNotBlank()) {
            return ResponseEntity.status(HttpStatus.FOUND)
                .header(HttpHeaders.LOCATION, apkUrl)
                .build()
        }

        val resources = mutableListOf<Resource>()

        if (apkFile.isNotBlank()) {
            resources.add(FileSystemResource(apkFile))
        }

        resources.add(ClassPathResource("static/download/rentana.apk"))

        val apk = resources.firstOrNull { it.exists() && it.isReadable }

        if (apk != null) {
            return ResponseEntity.ok()
                .header(
                    HttpHeaders.CONTENT_DISPOSITION,
                    "attachment; filename=\"rentana.apk\""
                )
                .contentType(MediaType.parseMediaType("application/vnd.android.package-archive"))
                .body(apk)
        }

        return ResponseEntity.status(HttpStatus.FOUND)
            .header(HttpHeaders.LOCATION, "/?download=missing#download")
            .build()
    }
}
