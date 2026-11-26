package com.tencent.bk.devops.iamstub.api

import com.fasterxml.jackson.databind.ObjectMapper
import org.hamcrest.Matchers.hasItem
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType.APPLICATION_JSON
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status
import com.tencent.bk.devops.iamstub.service.ApplicationService
import java.util.UUID

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class IamCallbackContractTest @Autowired constructor(
    val mockMvc: MockMvc,
    val applications: ApplicationService,
    val mapper: ObjectMapper
) {
    private val base = "/api/v2/open/management/systems/bk_ci_rbac"

    @Test
    fun `uuid callback id is accepted on approve and cancel`() {
        val uuid = UUID.randomUUID().toString()
        val body = mockMvc.perform(
            post("$base/grade_managers/-/applications/")
                .contentType(APPLICATION_JSON)
                .content("{\"name\":\"p\",\"applicant\":\"u1\",\"callback_id\":\"$uuid\",\"callback_url\":\"http://other:9000/cb\"}")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.sn").exists())
            .andReturn().response.contentAsString
        val sn = mapper.readTree(body).path("data").path("sn").asText()

        mockMvc.perform(
            post("$base/applications/$uuid/approve/")
                .contentType(APPLICATION_JSON).content("{\"sn\":\"$sn\",\"approve_result\":true}")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.id").isNumber)
            .andExpect(jsonPath("$.data.role_id").value(1001))

        mockMvc.perform(put("$base/applications/$uuid/cancel/"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.message").value("OK"))
    }

    @Test
    fun `grade manager detail has no trailing slash and usable fields`() {
        mockMvc.perform(get("$base/grade_managers/1001"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.id").value(1001))
            .andExpect(jsonPath("$.data.description").exists())
            .andExpect(jsonPath("$.data.creator").exists())
            .andExpect(jsonPath("$.data.sync_perm").exists())
            .andExpect(jsonPath("$.data.members", hasItem("demo")))
    }

    @Test
    fun `callback url from bk-ci is stored and preferred`() {
        val uuid = UUID.randomUUID().toString()
        mockMvc.perform(
            post("$base/grade_managers/-/applications/")
                .contentType(APPLICATION_JSON)
                .content("{\"name\":\"p\",\"callback_id\":\"$uuid\",\"callback_url\":\"http://other:9000/cb\"}")
        ).andExpect(status().isOk)
        org.assertj.core.api.Assertions.assertThat(applications.callbackUrlOf(uuid)).isEqualTo("http://other:9000/cb")
    }
}
