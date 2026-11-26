package com.tencent.bk.devops.iamstub.api

import com.tencent.bk.devops.iamstub.data.Ids
import com.tencent.bk.devops.iamstub.service.GroupStateService
import org.springframework.web.bind.annotation.DeleteMapping
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v2/open/management/systems/{system}")
class IamManagementController(private val groupState: GroupStateService) {

    @PostMapping("/grade_managers/")
    fun createGradeManager(
        @PathVariable system: String,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Int>> = ResponseEnvelope.ok(mapOf("id" to 1001))

    // IAM SDK 的 getGradeManagerDetail 请求无尾斜杠路径；批准回调后会读 members/description 更新管理员。
    @GetMapping("/grade_managers/{id}")
    fun getGradeManagerDetail(@PathVariable id: Int): ResponseEnvelope<Map<String, Any>> =
        ResponseEnvelope.ok(
            mapOf(
                "id" to id,
                "name" to "stub-manager",
                "description" to "local iam stub grade manager",
                "creator" to "admin",
                "members" to (groupState.allUserMembers() + "demo").distinct(),
                "sync_perm" to false
            )
        )

    @GetMapping("/grade_managers/{id}/")
    fun getGradeManager(@PathVariable id: Int): ResponseEnvelope<Map<String, Any>> =
        ResponseEnvelope.ok(mapOf("id" to id, "name" to "stub-manager"))

    @PutMapping("/grade_managers/{id}/")
    fun updateGradeManager(
        @PathVariable id: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> = ResponseEnvelope.ok(mapOf("id" to id))

    @DeleteMapping("/grade_managers/{id}/")
    fun deleteGradeManager(@PathVariable id: Int): ResponseEnvelope<Any?> = ResponseEnvelope.ok(null)

    @GetMapping("/grade_managers/{id}/groups/")
    fun listGradeManagerGroups(
        @PathVariable id: Int,
        @RequestParam(required = false) page: Int?,
        @RequestParam(name = "page_size", required = false) pageSize: Int?
    ): ResponseEnvelope<Map<String, Any>> = pagedGroups()

    @PostMapping("/grade_managers/{id}/groups/")
    fun createGroup(
        @PathVariable id: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<List<Int>> = ResponseEnvelope.ok(groupState.createGroup(id, body ?: emptyMap()))

    @PostMapping("/grade_managers/{id}/subset_managers/")
    fun createSubsetManager(
        @PathVariable id: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Int>> = ResponseEnvelope.ok(mapOf("id" to Ids.next()))

    @GetMapping("/subset_managers/{id}")
    fun getSubsetManager(@PathVariable id: Int): ResponseEnvelope<Map<String, Any>> =
        ResponseEnvelope.ok(mapOf("id" to id, "name" to "stub-subset"))

    @PostMapping("/subset_managers/{id}")
    fun updateSubsetManager(
        @PathVariable id: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> = ResponseEnvelope.ok(mapOf("id" to id))

    @DeleteMapping("/subset_managers/{id}/")
    fun deleteSubsetManager(@PathVariable id: Int): ResponseEnvelope<Any?> = ResponseEnvelope.ok(null)

    @GetMapping("/subset_managers/{id}/groups/")
    fun listSubsetGroups(@PathVariable id: Int): ResponseEnvelope<Map<String, Any>> = pagedGroups()

    @PutMapping("/groups/{groupId}/")
    fun updateGroup(
        @PathVariable groupId: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> = ResponseEnvelope.ok(mapOf("id" to groupId))

    @DeleteMapping("/groups/{groupId}/")
    fun deleteGroup(@PathVariable groupId: Int): ResponseEnvelope<Any?> = ResponseEnvelope.ok(null)

    @GetMapping("/groups/{groupId}/policies/")
    fun listPolicies(@PathVariable groupId: Int): ResponseEnvelope<Map<String, Any>> =
        ResponseEnvelope.ok(mapOf("count" to 0, "results" to emptyList<Any>()))

    @PostMapping("/groups/{groupId}/policies/")
    fun addPolicies(
        @PathVariable groupId: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> = ResponseEnvelope.ok(emptyMap())

    @GetMapping("/groups/{groupId}/policies/-/actions/")
    fun listPolicyActions(@PathVariable groupId: Int): ResponseEnvelope<List<Any>> =
        ResponseEnvelope.ok(emptyList())

    @GetMapping("/groups/{groupId}/members/")
    fun listMembers(@PathVariable groupId: Int): ResponseEnvelope<Map<String, Any>> {
        val results = groupState.listMembers(groupId).map { m ->
            mapOf(
                "id" to m.memberId,
                "type" to m.type,
                "expired_at" to m.expiredAt,
                "created_at" to 0L
            )
        }
        return ResponseEnvelope.ok(mapOf("count" to results.size, "results" to results))
    }

    @PostMapping("/groups/{groupId}/members/")
    fun addMembers(
        @PathVariable groupId: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> {
        groupState.addMember(groupId, body ?: emptyMap())
        return ResponseEnvelope.ok(emptyMap())
    }

    @DeleteMapping("/groups/{groupId}/members/")
    fun deleteMembers(
        @PathVariable groupId: Int,
        @RequestParam ids: String?
    ): ResponseEnvelope<Map<String, Any>> {
        groupState.removeMembers(groupId, ids?.split(",")?.filter { it.isNotBlank() } ?: emptyList())
        return ResponseEnvelope.ok(emptyMap())
    }

    @PutMapping("/groups/{groupId}/members/-/expired_at/")
    fun updateMemberExpiredAt(
        @PathVariable groupId: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> = ResponseEnvelope.ok(emptyMap())

    @GetMapping("/users/{userId}/groups/belong/")
    fun userGroupsBelong(
        @PathVariable userId: String,
        @RequestParam(name = "group_ids", required = false) groupIds: String?
    ): ResponseEnvelope<Map<String, Map<String, Any>>> = belongResult(userId, groupIds)

    @GetMapping("/departments/{deptId}/groups/belong/")
    fun departmentGroupsBelong(
        @PathVariable deptId: String,
        @RequestParam(name = "group_ids", required = false) groupIds: String?
    ): ResponseEnvelope<Map<String, Map<String, Any>>> = belongResult(deptId, groupIds)

    @GetMapping("/group_member_types/{type}/members/{memberId}/groups/-/details/")
    fun memberGroupDetails(
        @PathVariable type: String,
        @PathVariable memberId: String,
        @RequestParam(name = "group_ids", required = false) groupIds: String?
    ): ResponseEnvelope<List<Map<String, Any>>> {
        val ids = groupIds?.split(",")?.filter { it.isNotBlank() }?.mapNotNull { it.toIntOrNull() }
            ?: groupState.allGroups().map { it.id }
        return ResponseEnvelope.ok(ids.map { id ->
            val detail = groupState.detailOf(id)
            mapOf(
                "id" to id,
                "name" to (detail["name"] ?: ""),
                "description" to (detail["description"] ?: ""),
                "created_at" to 0L,
                "expired_at" to 0L
            )
        })
    }

    @GetMapping("/grade_managers/{id}/subject_templates/")
    fun gradeManagerSubjectTemplates(@PathVariable id: Int): ResponseEnvelope<Map<String, Any>> =
        ResponseEnvelope.ok(mapOf("count" to 0, "results" to emptyList<Any>()))

    @GetMapping("/groups/{groupId}/subject_templates/")
    fun groupSubjectTemplates(@PathVariable groupId: Int): ResponseEnvelope<Map<String, Any>> =
        ResponseEnvelope.ok(mapOf("count" to 0, "results" to emptyList<Any>()))

    private fun pagedGroups(): ResponseEnvelope<Map<String, Any>> {
        val groups = groupState.allGroups()
        return ResponseEnvelope.ok(
            mapOf("count" to groups.size, "results" to groups.map { groupState.detailOf(it.id) })
        )
    }

    private fun belongResult(
        memberId: String,
        groupIds: String?
    ): ResponseEnvelope<Map<String, Map<String, Any>>> {
        val ids = groupIds?.split(",")?.filter { it.isNotBlank() }?.mapNotNull { it.toIntOrNull() }
            ?: emptyList()
        return ResponseEnvelope.ok(ids.associate { gid ->
            gid.toString() to mapOf(
                "belong" to groupState.memberBelongs(memberId, gid),
                "expired_at" to 0L,
                "created_at" to 0L,
                "is_direct_added" to true
            )
        })
    }
}
