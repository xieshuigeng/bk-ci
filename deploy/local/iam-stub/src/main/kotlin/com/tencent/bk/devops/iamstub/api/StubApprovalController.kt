package com.tencent.bk.devops.iamstub.api

import com.tencent.bk.devops.iamstub.data.TicketRepo
import com.tencent.bk.devops.iamstub.service.ApplicationService
import com.tencent.bk.devops.iamstub.service.ItsmCallbackService
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RestController

@RestController
class StubApprovalController(
    private val ticketRepo: TicketRepo,
    private val applications: ApplicationService,
    private val itsmCallbacks: ItsmCallbackService
) {

    @PostMapping("/itsm-stub/api/approve")
    fun approveItsmTicket(@RequestBody(required = false) body: Map<String, Any>?): ResponseEnvelope<Map<String, Boolean>> {
        val payload = body ?: emptyMap()
        val sn = payload["sn"]?.toString() ?: return ResponseEnvelope.ok(mapOf("ok" to false))
        val approved = payload["approved"] as? Boolean ?: true
        val ticket = ticketRepo.findById(sn).orElse(null)
        if (ticket != null) {
            applications.approve(ticket.callbackId, payload)
            itsmCallbacks.notifyApproval(
                sn = sn,
                approved = approved,
                callbackUrl = payload["callbackUrl"]?.toString(),
                applicant = payload["applicant"]?.toString() ?: "demo",
                lastApprover = payload["lastApprover"]?.toString() ?: "admin"
            )
        }
        return ResponseEnvelope.ok(mapOf("ok" to true))
    }

    @PostMapping("/stub/api/approve-group")
    fun approveGroup(@RequestBody(required = false) body: Map<String, Any>?): ResponseEnvelope<Map<String, Boolean>> {
        val payload = body ?: emptyMap()
        val id = (payload["id"] as? Number)?.toInt() ?: return ResponseEnvelope.ok(mapOf("ok" to false))
        val approved = payload["approved"] as? Boolean ?: true
        if (approved) {
            applications.approve(id, payload)
        }
        return ResponseEnvelope.ok(mapOf("ok" to true))
    }
}
