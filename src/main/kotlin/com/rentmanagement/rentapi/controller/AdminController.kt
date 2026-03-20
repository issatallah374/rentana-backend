package com.rentmanagement.rentapi.controllers

import org.springframework.stereotype.Controller
import org.springframework.web.bind.annotation.GetMapping

@Controller
class AdminController {

    @GetMapping("/admin")
    fun dashboard(): String {
        return "admin/dashboard"
    }

    @GetMapping("/admin/payouts")
    fun payouts(): String {
        return "admin/payouts"
    }

    @GetMapping("/admin/users")
    fun users(): String {
        return "admin/users"
    }

    @GetMapping("/admin/wallet")
    fun wallet(): String {
        return "admin/wallet"
    }
}