package com.tencent.bk.devops.iamstub.service

import com.tencent.bk.devops.iamstub.data.ApplicationRepo
import com.tencent.bk.devops.iamstub.data.Ids
import com.tencent.bk.devops.iamstub.data.StubApplication
import com.tencent.bk.devops.iamstub.data.StubTicket
import com.tencent.bk.devops.iamstub.data.TicketRepo
import com.tencent.bk.devops.iamstub.data.snOf
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service

@Service
class ApplicationService(
    private val applicationRepo: ApplicationRepo,
    private val ticketRepo: TicketRepo,
    private val groupState: GroupStateService,
    private val jdbcTemplate: JdbcTemplate
) {

    fun createGroupApplication(body: Map<String, Any>): List<Int> {
        val n = Ids.next()
        val groupIds = (body["group_ids"] as? List<*>)?.joinToString(",") { it.toString() } ?: ""
        val applicant = body["applicant"]?.toString() ?: "demo"
        insertApplication(n, snOf(n), groupIds, applicant, "PENDING", n, null)
        return listOf(n)
    }

    fun createGradeManagerApplication(body: Map<String, Any>): Pair<Int, String> {
        val n = Ids.next()
        val sn = snOf(n)
        val applicant = body["applicant"]?.toString() ?: "demo"
        // bk-ci SDK 传来的 callback_id 是 UUID，必须原样保存；approve/cancel 时用它定位单据。
        val externalCallbackId = body["callback_id"]?.toString()?.takeIf { it.isNotBlank() }
        val callbackUrl = body["callback_url"]?.toString()?.takeIf { it.isNotBlank() }
        insertApplication(n, sn, "", applicant, "PENDING", n, externalCallbackId)
        jdbcTemplate.update(
            "INSERT INTO \"stub_ticket\" " +
                "(sn, status, token, callback_id, apply_id, external_callback_id, callback_url) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
            sn, "RUNNING", "stub-token", n, n, externalCallbackId, callbackUrl
        )
        return n to sn
    }

    fun approve(callbackId: String, body: Map<String, Any>): Pair<Int, Int> {
        val roleId = 1001
        val application = findApplication(callbackId, body["sn"]?.toString())
        // 兼容老测试/手工调用中的数字 callbackId；真实 bk-ci 传 UUID 时用落库的自增 id 回包。
        val id = callbackId.toIntOrNull() ?: application?.id ?: 0
        if (application != null) {
            application.groupIds.split(",").filter { it.isNotBlank() }.forEach { gid ->
                val groupId = gid.toIntOrNull() ?: return@forEach
                groupState.addMember(
                    groupId,
                    mapOf(
                        "members" to listOf(mapOf<String, Any>("type" to "USER", "id" to application.applicant)),
                        "expired_at" to 0L
                    )
                )
            }
            jdbcTemplate.update(
                "UPDATE \"stub_application\" SET status = ?, approve_result = ? WHERE id = ?",
                "APPROVED", "true", application.id
            )
        }
        val sn = body["sn"]?.toString()
        if (sn != null) {
            jdbcTemplate.update("UPDATE \"stub_ticket\" SET status = ? WHERE sn = ?", "FINISHED", sn)
        } else {
            ticketsFor(callbackId, application?.id).forEach { ticket ->
                jdbcTemplate.update("UPDATE \"stub_ticket\" SET status = ? WHERE sn = ?", "FINISHED", ticket.sn)
            }
        }
        return id to roleId
    }

    fun cancel(callbackId: String): Boolean {
        val application = findApplication(callbackId, null)
        val id = callbackId.toIntOrNull() ?: application?.id
        if (id != null) {
            jdbcTemplate.update("UPDATE \"stub_application\" SET status = ? WHERE id = ?", "CANCELLED", id)
        }
        ticketsFor(callbackId, application?.id).forEach { ticket ->
            jdbcTemplate.update("UPDATE \"stub_ticket\" SET status = ? WHERE sn = ?", "CANCELLED", ticket.sn)
        }
        return true
    }

    fun callbackUrlOf(externalCallbackId: String): String? =
        ticketRepo.findByExternalCallbackId(externalCallbackId).firstOrNull()?.callbackUrl

    private fun findApplication(callbackId: String, sn: String?): StubApplication? {
        applicationRepo.findByExternalCallbackId(callbackId).firstOrNull()?.let { return it }
        if (sn != null) {
            applicationRepo.findBySn(sn).firstOrNull()?.let { return it }
        }
        return callbackId.toIntOrNull()?.let { applicationRepo.findById(it).orElse(null) }
    }

    private fun ticketsFor(callbackId: String, id: Int?): List<StubTicket> {
        val byExternal = ticketRepo.findByExternalCallbackId(callbackId)
        if (byExternal.isNotEmpty()) return byExternal
        return id?.let { ticketRepo.findByCallbackId(it) } ?: emptyList()
    }

    private fun insertApplication(
        id: Int,
        sn: String,
        groupIds: String,
        applicant: String,
        status: String,
        callbackId: Int,
        externalCallbackId: String?
    ) {
        jdbcTemplate.update(
            "INSERT INTO \"stub_application\" " +
                "(id, sn, group_ids, applicant, status, callback_id, external_callback_id) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
            id, sn, groupIds, applicant, status, callbackId, externalCallbackId
        )
    }
}
