package com.tencent.bk.devops.iamstub.api

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping
class IamBasicController {

    @GetMapping("/api/v1/model/systems/{system}/token")
    fun token(@PathVariable system: String): ResponseEnvelope<Map<String, String>> =
        ResponseEnvelope.ok(mapOf("token" to "stub-token"))

    @GetMapping("/api/v1/model/systems/{system}/query")
    fun modelQuery(@PathVariable system: String): ResponseEnvelope<Map<String, Any>> =
        ResponseEnvelope.ok(
            mapOf(
                "base_info" to mapOf("id" to system, "name" to system),
                "resource_types" to emptyList<Any>(),
                "actions" to emptyList<Any>(),
                "instance_selections" to emptyList<Any>(),
                "action_groups" to emptyList<Any>()
            )
        )

    @PostMapping("/api/v2/policy/systems/{system}/auth/")
    fun auth(
        @PathVariable system: String,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Boolean>> = ResponseEnvelope.ok(mapOf("allowed" to true))

    @PostMapping("/api/v2/policy/systems/{system}/auth_by_actions/")
    fun authByActions(
        @PathVariable system: String,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Boolean>> {
        val actions = body?.get("actions") as? List<*> ?: emptyList<Any>()
        return ResponseEnvelope.ok(actions.associate { it.toString() to true })
    }

    @PostMapping("/api/v2/policy/systems/{system}/query/")
    fun query(
        @PathVariable system: String,
        @RequestBody(required = false) body: Map<String, Any>?
    ): ResponseEnvelope<Map<String, Any>> =
        ResponseEnvelope.ok(mapOf("op" to "AND", "content" to emptyList<Any>()))
}
