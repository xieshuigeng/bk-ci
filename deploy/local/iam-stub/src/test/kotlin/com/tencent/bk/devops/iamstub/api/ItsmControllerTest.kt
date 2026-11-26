package com.tencent.bk.devops.iamstub.api

import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest
import org.springframework.boot.test.mock.mockito.MockBean
import org.springframework.http.MediaType.APPLICATION_JSON
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status
import com.tencent.bk.devops.iamstub.data.StubTicket
import com.tencent.bk.devops.iamstub.data.TicketRepo
import org.mockito.Mockito.`when`
import java.util.Optional

@WebMvcTest(ItsmController::class)
class ItsmControllerTest @Autowired constructor(val mockMvc: MockMvc) {

    @MockBean
    lateinit var ticketRepo: TicketRepo

    @Test
    fun `token verify passes`() {
        mockMvc.perform(post("/token/verify/").contentType(APPLICATION_JSON).content("{\"token\":\"stub-token\"}"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.code").value(0))
            .andExpect(jsonPath("$.data.is_passed").value(true))
    }

    @Test
    fun `operate ticket has success message`() {
        mockMvc.perform(post("/operate_ticket/").contentType(APPLICATION_JSON).content("{}"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.message").value("success"))
    }

    @Test
    fun `ticket status reflects stored status`() {
        `when`(ticketRepo.findById("STUB-1")).thenReturn(
            Optional.of(StubTicket("STUB-1", "RUNNING", "stub-token", 1, 1))
        )
        mockMvc.perform(get("/get_ticket_status?sn=STUB-1"))
            .andExpect(status().isOk)
            .andExpect(jsonPath("$.data.current_status").value("RUNNING"))
    }
}
