package com.rentmanagement.rentapi

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication
import org.springframework.scheduling.annotation.EnableScheduling

@SpringBootApplication
@EnableScheduling
class RentApiApplication

fun main(args: Array<String>) {
    runApplication<RentApiApplication>(*args)
}