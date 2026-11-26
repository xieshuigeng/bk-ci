package com.tencent.bk.devops.iamstub.api

import org.hamcrest.Matchers.matchesPattern
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.http.MediaType.APPLICATION_JSON
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class IamApplicationControllerTest @Autowired constructor(val mockMvc: MockMvc) {

    @Test
    fun `grade manager application returns exact id and sn`() {
        mockMvc.perform(
            post("/api/v2/open/management/systems/bk_ci_rbac/grade_managers/-/applications/")
                .contentType(APPLICATION_JSON).content("{\"name\":\"p\",\"callback_id\":\"cb-1\"}")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.code").value(0))
            .andExpect(jsonPath("$.data.id").isNumber)
            .andExpect(jsonPath("$.data.sn", matchesPattern("STUB-\\d+")))
    }

    @Test
    fun `approve returns id and role_id and cancel message is OK`() {
        mockMvc.perform(
            post("/api/v2/open/management/systems/bk_ci_rbac/applications/9/approve/")
                .contentType(APPLICATION_JSON).content("{\"sn\":\"STUB-9\",\"approve_result\":true}")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.id").value(9))
            .andExpect(jsonPath("$.data.role_id").value(1001))
        mockMvc.perform(put("/api/v2/open/management/systems/bk_ci_rbac/applications/9/cancel/"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.message").value("OK"))
    }

    @Test
    fun `group application returns numeric ids`() {
        mockMvc.perform(
            post("/api/v2/open/management/systems/bk_ci_rbac/groups/-/applications/")
                .contentType(APPLICATION_JSON).content("{\"group_ids\":[10001],\"applicant\":\"u1\"}")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.ids").isArray)
            .andExpect(jsonPath("$.data.ids[0]").isNumber)
    }
}
