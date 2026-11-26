package com.tencent.bk.devops.iamstub.service

import com.tencent.bk.devops.iamstub.data.TicketRepo
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import org.springframework.web.client.RestTemplate

@Service
class ItsmCallbackService(
    private val restTemplate: RestTemplate,
    private val ticketRepo: TicketRepo,
    @Value("\${stub.callback-base-url:http://gateway:80}") private val baseUrl: String
) {
    private val logger = LoggerFactory.getLogger(javaClass)

    fun notifyApproval(
        sn: String,
        approved: Boolean,
        callbackUrl: String?,
        applicant: String,
        lastApprover: String
    ) {
        // 回调用容器网可达地址；localhost/127.0.0.1 在容器内不指向 bk-ci，直接回退到 baseUrl。
        val explicit = callbackUrl?.takeIf {
            it.isNotBlank() && !it.contains("localhost") && !it.contains("127.0.0.1")
        }
        val target = explicit
            ?: "$baseUrl/ms/auth/api/external/auth/itsm/" +
                if (approved) "create_callback" else "update_callback"
        val token = ticketRepo.findById(sn).orElse(null)?.token ?: "stub-token"
        val body = mapOf(
            "title" to "bk-ci 本地审批通知",
            "current_status" to if (approved) "FINISHED" else "CANCELLED",
            "sn" to sn,
            "ticket_url" to "$baseUrl/itsm-stub/#/ticket/approval-iframe",
            "update_at" to System.currentTimeMillis(),
            "updated_by" to lastApprover,
            "approve_result" to approved.toString(),
            "token" to token,
            "last_approver" to lastApprover,
            "applicant" to applicant
        )
        try {
            restTemplate.postForEntity(target, body, String::class.java)
        } catch (e: Exception) {
            logger.warn("itsm callback failed for $sn -> $target", e)
        }
    }
}
