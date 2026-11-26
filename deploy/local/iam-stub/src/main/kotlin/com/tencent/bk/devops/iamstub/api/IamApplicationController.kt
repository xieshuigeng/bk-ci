package com.tencent.bk.devops.iamstub.api

import com.tencent.bk.devops.iamstub.service.ApplicationService
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.PutMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v2/open/management/systems/{system}")
class IamApplicationController(private val applications: ApplicationService) {

    @PostMapping("/groups/-/applications/")
    fun createGroupApplication(
        @PathVariable system: String,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, List<Int>>> =
        ResponseEnvelope.ok(mapOf("ids" to applications.createGroupApplication(body ?: emptyMap())))

    @PostMapping("/groups/-/renew/applications/")
    fun renewGroupApplication(
        @PathVariable system: String,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> = ResponseEnvelope.ok(emptyMap())

    @PostMapping("/grade_managers/-/applications/")
    fun createGradeManagerApplication(
        @PathVariable system: String,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> = gradeManagerResult(body)

    @PostMapping("/grade_managers/{id}/applications/")
    fun createGradeManagerApplicationForManager(
        @PathVariable system: String,
        @PathVariable id: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> = gradeManagerResult(body)

    @PostMapping("/applications/{callbackId}/approve/")
    fun approveApplication(
        @PathVariable system: String,
        @PathVariable callbackId: Int,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Int>> {
        val (id, roleId) = applications.approve(callbackId, body ?: emptyMap())
        return ResponseEnvelope.ok(mapOf("id" to id, "role_id" to roleId))
    }

    @PutMapping("/applications/{callbackId}/cancel/")
    fun cancelApplication(
        @PathVariable system: String,
        @PathVariable callbackId: Int
    ): ResponseEnvelope<Any?> {
        applications.cancel(callbackId)
        return ResponseEnvelope(message = "OK", data = null)
    }

    private fun gradeManagerResult(body: Map<String, Any>?): ResponseEnvelope<Map<String, Any>> {
        val (id, sn) = applications.createGradeManagerApplication(body ?: emptyMap())
        return ResponseEnvelope.ok(mapOf("id" to id, "sn" to sn))
    }
}
