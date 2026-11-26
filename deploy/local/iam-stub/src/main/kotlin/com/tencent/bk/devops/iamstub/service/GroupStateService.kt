package com.tencent.bk.devops.iamstub.service

import com.tencent.bk.devops.iamstub.data.GroupRepo
import com.tencent.bk.devops.iamstub.data.Ids
import com.tencent.bk.devops.iamstub.data.MemberRepo
import com.tencent.bk.devops.iamstub.data.StubGroup
import com.tencent.bk.devops.iamstub.data.StubMember
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Service

@Service
class GroupStateService(
    private val groupRepo: GroupRepo,
    private val memberRepo: MemberRepo,
    private val jdbcTemplate: JdbcTemplate
) {

    @Suppress("UNCHECKED_CAST")
    fun createGroup(gradeManagerId: Int, body: Map<String, Any>): List<Int> {
        val names = body["names"] as? List<String>
            ?: body["name"]?.let { listOf(it.toString()) }
            ?: listOf("stub-group")
        return names.map { name ->
            val id = Ids.next()
            jdbcTemplate.update(
                "INSERT INTO \"stub_group\" (id, name, description, project) VALUES (?, ?, ?, ?)",
                id, name, name, "stub-demo"
            )
            id
        }
    }

    @Suppress("UNCHECKED_CAST")
    fun addMember(groupId: Int, body: Map<String, Any>) {
        val expiredAt = (body["expired_at"] as? Number)?.toLong() ?: 0L
        val members = body["members"] as? List<Map<String, Any>> ?: emptyList()
        members.forEach { m ->
            val type = m["type"]?.toString() ?: "USER"
            val id = m["id"]?.toString() ?: return@forEach
            if (memberRepo.findByGroupIdAndMemberId(groupId, id).isEmpty()) {
                memberRepo.save(
                    StubMember(groupId = groupId, type = type, memberId = id, expiredAt = expiredAt)
                )
            }
        }
    }

    fun removeMembers(groupId: Int, ids: List<String>) {
        ids.forEach { id ->
            memberRepo.findByGroupIdAndMemberId(groupId, id).forEach { memberRepo.delete(it) }
        }
    }

    fun memberBelongs(userId: String, groupId: Int): Boolean =
        memberRepo.findByGroupIdAndMemberId(groupId, userId).isNotEmpty()

    fun listMembers(groupId: Int): List<StubMember> = memberRepo.findByGroupId(groupId)

    fun detailOf(groupId: Int): Map<String, Any> {
        val group: StubGroup? = groupRepo.findById(groupId).orElse(null)
        val members = listMembers(groupId)
        return mapOf(
            "id" to groupId,
            "name" to (group?.name ?: "group-$groupId"),
            "description" to (group?.description ?: ""),
            "readonly" to false,
            "user_count" to members.count { it.type == "USER" },
            "department_count" to members.count { it.type == "DEPARTMENT" },
            "subject_template_count" to 0,
            "joined" to false,
            "apply_disable" to false
        )
    }

    fun allGroups(): List<StubGroup> = groupRepo.findAll().toList()
}
