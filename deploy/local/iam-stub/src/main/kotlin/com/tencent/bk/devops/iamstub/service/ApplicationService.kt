package com.tencent.bk.devops.iamstub.service

import com.tencent.bk.devops.iamstub.data.ApplicationRepo
import com.tencent.bk.devops.iamstub.data.Ids
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
        insertApplication(n, snOf(n), groupIds, applicant, "PENDING", n)
        return listOf(n)
    }

    fun createGradeManagerApplication(body: Map<String, Any>): Pair<Int, String> {
        val n = Ids.next()
        val sn = snOf(n)
        val applicant = body["applicant"]?.toString() ?: "demo"
        insertApplication(n, sn, "", applicant, "PENDING", n)
        jdbcTemplate.update(
            "INSERT INTO \"stub_ticket\" (sn, status, token, callback_id, apply_id) VALUES (?, ?, ?, ?, ?)",
            sn, "RUNNING", "stub-token", n, n
        )
        return n to sn
    }

    fun approve(callbackId: Int, body: Map<String, Any>): Pair<Int, Int> {
        val roleId = 1001
        val application = applicationRepo.findById(callbackId).orElse(null)
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
                "APPROVED", "true", callbackId
            )
        }
        val sn = body["sn"]?.toString()
        if (sn != null) {
            jdbcTemplate.update(
                "UPDATE \"stub_ticket\" SET status = ? WHERE sn = ?",
                "FINISHED", sn
            )
        } else {
            ticketRepo.findByCallbackId(callbackId).forEach { ticket ->
                jdbcTemplate.update(
                    "UPDATE \"stub_ticket\" SET status = ? WHERE sn = ?",
                    "FINISHED", ticket.sn
                )
            }
        }
        return callbackId to roleId
    }

    fun cancel(callbackId: Int): Boolean {
        jdbcTemplate.update("UPDATE \"stub_application\" SET status = ? WHERE id = ?", "CANCELLED", callbackId)
        ticketRepo.findByCallbackId(callbackId).forEach { ticket ->
            jdbcTemplate.update("UPDATE \"stub_ticket\" SET status = ? WHERE sn = ?", "CANCELLED", ticket.sn)
        }
        return true
    }

    private fun insertApplication(
        id: Int,
        sn: String,
        groupIds: String,
        applicant: String,
        status: String,
        callbackId: Int
    ) {
        jdbcTemplate.update(
            "INSERT INTO \"stub_application\" (id, sn, group_ids, applicant, status, callback_id) VALUES (?, ?, ?, ?, ?, ?)",
            id, sn, groupIds, applicant, status, callbackId
        )
    }
}
