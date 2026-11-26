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
            val callbackId = ticket.externalCallbackId ?: ticket.callbackId.toString()
            if (approved) {
                applications.approve(callbackId, payload + mapOf("sn" to sn))
            } else {
                applications.cancel(callbackId)
            }
            itsmCallbacks.notifyApproval(
                sn = sn,
                approved = approved,
                // 页面按钮不传 callbackUrl，此时用 bk-ci 创建工单时传入并落库的地址。
                callbackUrl = payload["callbackUrl"]?.toString()?.takeIf { it.isNotBlank() } ?: ticket.callbackUrl,
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
            applications.approve(id.toString(), payload)
        } else {
            applications.cancel(id.toString())
        }
        return ResponseEnvelope.ok(mapOf("ok" to true))
    }
}
