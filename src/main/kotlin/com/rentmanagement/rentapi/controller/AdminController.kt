package com.rentmanagement.rentapi.controllers

import org.springframework.stereotype.Controller
import org.springframework.web.bind.annotation.GetMapping

@Controller
class AdminController {

    // =========================
    // 🔐 LOGIN PAGE
    // =========================
    @GetMapping("/admin/login")
    fun login(): String {
        return "admin/login"
    }

    // =========================
    // 🏠 HOME (MENU)
    // =========================
    @GetMapping("/admin")
    fun index(): String {
        return "admin/index"
    }

    // =========================
    // 📊 MAIN DASHBOARD
    // =========================
    @GetMapping("/admin/dashboard")
    fun dashboard(): String {
        return "admin/dashboard"
    }

    // =========================
    // OPTIONAL PAGES
    // =========================
    @GetMapping("/admin/payouts")
    fun payouts(): String {
        return "admin/dashboard"
    }

    @GetMapping("/admin/users")
    fun users(): String {
        return "admin/dashboard"
    }

    @GetMapping("/admin/wallet")
    fun wallet(): String {
        return "admin/dashboard"
    }
}