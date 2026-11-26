package com.tencent.bk.devops.iamstub.api

import com.fasterxml.jackson.databind.ObjectMapper
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType.APPLICATION_JSON
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class StubApprovalControllerTest @Autowired constructor(
    val mockMvc: MockMvc,
    val mapper: ObjectMapper,
    val jdbcTemplate: JdbcTemplate
) {
    @Test
    fun `rejecting a group application cancels instead of approving`() {
        val body = mockMvc.perform(
            post("/api/v2/open/management/systems/bk_ci_rbac/groups/-/applications/")
                .contentType(APPLICATION_JSON)
                .content("{\"group_ids\":[10001],\"applicant\":\"reject-user\"}")
        ).andExpect(status().isOk).andReturn().response.contentAsString
        val id = mapper.readTree(body).path("data").path("ids").path(0).asInt()

        mockMvc.perform(
            post("/stub/api/approve-group")
                .contentType(APPLICATION_JSON)
                .content("{\"id\":$id,\"approved\":false}")
        ).andExpect(status().isOk)

        val status = jdbcTemplate.queryForObject(
            "SELECT status FROM \"stub_application\" WHERE id = ?", String::class.java, id
        )
        assertThat(status).isEqualTo("CANCELLED")
    }
}
