package com.tencent.bk.devops.iamstub.api

import com.tencent.bk.devops.iamstub.data.TicketRepo
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
class ItsmController(private val ticketRepo: TicketRepo) {

    @PostMapping("/token/verify/")
    fun verifyToken(@RequestBody(required = false) body: Map<String, Any>?): ResponseEnvelope<Map<String, Boolean>> =
        ResponseEnvelope.ok(mapOf("is_passed" to true))

    @GetMapping("/get_ticket_status")
    fun ticketStatus(@RequestParam sn: String): ResponseEnvelope<Map<String, String>> {
        val status = ticketRepo.findById(sn).orElse(null)?.status ?: "RUNNING"
        return ResponseEnvelope.ok(mapOf("current_status" to status))
    }

    @PostMapping("/operate_ticket/")
    fun operateTicket(@RequestBody(required = false) body: Map<String, Any>?): ResponseEnvelope<Any?> =
        ResponseEnvelope(message = "success", data = null)
}
