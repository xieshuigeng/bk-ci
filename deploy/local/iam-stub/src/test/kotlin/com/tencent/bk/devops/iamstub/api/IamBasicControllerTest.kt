package com.tencent.bk.devops.iamstub.api

import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest
import org.springframework.http.MediaType.APPLICATION_JSON
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

@WebMvcTest(IamBasicController::class)
class IamBasicControllerTest @Autowired constructor(val mockMvc: MockMvc) {

    @Test
    fun `token endpoint returns numeric code and stub token`() {
        mockMvc.perform(get("/api/v1/model/systems/bk_ci_rbac/token"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.code").value(0))
            .andExpect(jsonPath("$.data.token").value("stub-token"))
    }

    @Test
    fun `IAM responses carry X-Request-Id required by SDK`() {
        mockMvc.perform(get("/api/v1/model/systems/bk_ci_rbac/token"))
            .andExpect(status().isOk)
            .andExpect(
                org.springframework.test.web.servlet.result.MockMvcResultMatchers.header()
                    .string("X-Request-Id", org.hamcrest.Matchers.not(org.hamcrest.Matchers.emptyOrNullString()))
            )
    }

    @Test
    fun `model query returns all five sections`() {
        mockMvc.perform(get("/api/v1/model/systems/bk_ci_rbac/query"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.base_info").exists())
            .andExpect(jsonPath("$.data.resource_types").isArray)
            .andExpect(jsonPath("$.data.actions").isArray)
            .andExpect(jsonPath("$.data.instance_selections").isArray)
            .andExpect(jsonPath("$.data.action_groups").isArray)
    }

    @Test
    fun `policy auth and query endpoints return allowed`() {
        mockMvc.perform(
            post("/api/v2/policy/systems/bk_ci_rbac/auth/")
                .contentType(APPLICATION_JSON).content("{}")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.allowed").value(true))
        mockMvc.perform(
            post("/api/v2/policy/systems/bk_ci_rbac/auth_by_actions/")
                .contentType(APPLICATION_JSON).content("{\"actions\":[\"access_project\"]}")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.access_project").value(true))
        mockMvc.perform(
            post("/api/v2/policy/systems/bk_ci_rbac/query/")
                .contentType(APPLICATION_JSON).content("{}")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.op").value("any"))
    }
}
