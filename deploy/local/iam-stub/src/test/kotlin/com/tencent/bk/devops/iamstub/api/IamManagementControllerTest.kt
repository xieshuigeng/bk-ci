package com.tencent.bk.devops.iamstub.api

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
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class IamManagementControllerTest @Autowired constructor(val mockMvc: MockMvc) {

    @Test
    fun `group list has count and results`() {
        mockMvc.perform(
            get("/api/v2/open/management/systems/bk_ci_rbac/grade_managers/1001/groups/?page=1&page_size=10")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.code").value(0))
            .andExpect(jsonPath("$.data.count").isNumber)
            .andExpect(jsonPath("$.data.results").isArray)
    }

    @Test
    fun `update subset manager is POST without trailing slash`() {
        mockMvc.perform(
            post("/api/v2/open/management/systems/bk_ci_rbac/subset_managers/2001")
                .contentType(APPLICATION_JSON).content("{}")
        )
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.code").value(0))
    }

    @Test
    fun `belong and members agree after add`() {
        mockMvc.perform(
            post("/api/v2/open/management/systems/bk_ci_rbac/groups/10001/members/")
                .contentType(APPLICATION_JSON)
                .content("{\"members\":[{\"type\":\"USER\",\"id\":\"u1\"}],\"expired_at\":0}")
        )
            .andExpect(status().isOk)
        mockMvc.perform(
            get("/api/v2/open/management/systems/bk_ci_rbac/users/u1/groups/belong/?group_ids=10001")
        )
            .andExpect(jsonPath("$.data['10001'].belong").value(true))
        mockMvc.perform(get("/api/v2/open/management/systems/bk_ci_rbac/groups/10001/members/"))
            .andExpect(jsonPath("$.data.results[*].id", hasItem("u1")))
    }
}
