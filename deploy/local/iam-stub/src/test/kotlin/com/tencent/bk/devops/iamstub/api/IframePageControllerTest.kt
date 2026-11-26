package com.tencent.bk.devops.iamstub.api

import org.hamcrest.Matchers.containsString
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.content
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class IframePageControllerTest @Autowired constructor(
    val mockMvc: MockMvc,
    val jdbcTemplate: JdbcTemplate
) {

    @Test
    fun `apply page lists pending application and approval endpoint`() {
        insertPendingApplication()
        mockMvc.perform(get("/iam-stub/apply"))
            .andExpect(status().isOk)
            .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
            .andExpect(content().string(containsString("STUB-7777")))
            .andExpect(content().string(containsString("/stub/api/approve-group")))
    }

    @Test
    fun `itsm page lists ticket and approval endpoint`() {
        insertTicket()
        mockMvc.perform(get("/itsm-stub/"))
            .andExpect(status().isOk)
            .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
            .andExpect(content().string(containsString("STUB-7777")))
            .andExpect(content().string(containsString("/itsm-stub/api/approve")))
    }

    private fun insertPendingApplication() {
        jdbcTemplate.update(
            "MERGE INTO \"stub_application\" (id, sn, group_ids, applicant, status, callback_id) KEY(id) VALUES (?, ?, ?, ?, ?, ?)",
            7777, "STUB-7777", "10001", "iframe-user", "PENDING", 7777
        )
    }

    private fun insertTicket() {
        jdbcTemplate.update(
            "MERGE INTO \"stub_ticket\" (sn, status, token, callback_id, apply_id) KEY(sn) VALUES (?, ?, ?, ?, ?)",
            "STUB-7777", "RUNNING", "stub-token", 7777, 7777
        )
    }
}
