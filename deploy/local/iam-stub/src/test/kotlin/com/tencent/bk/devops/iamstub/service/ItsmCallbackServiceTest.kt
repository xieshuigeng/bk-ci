package com.tencent.bk.devops.iamstub.service

import com.tencent.bk.devops.iamstub.data.StubTicket
import com.tencent.bk.devops.iamstub.data.TicketRepo
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.Mockito.`when`
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.mock.mockito.MockBean
import org.springframework.http.HttpMethod
import org.springframework.http.MediaType.APPLICATION_JSON
import org.springframework.test.context.ActiveProfiles
import org.springframework.test.web.client.MockRestServiceServer
import org.springframework.test.web.client.match.MockRestRequestMatchers.content
import org.springframework.test.web.client.match.MockRestRequestMatchers.method
import org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo
import org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess
import org.springframework.web.client.RestTemplate
import java.util.Optional

@SpringBootTest
@ActiveProfiles("test")
class ItsmCallbackServiceTest @Autowired constructor(
    private val service: ItsmCallbackService,
    private val restTemplate: RestTemplate
) {
    @MockBean
    lateinit var ticketRepo: TicketRepo

    private lateinit var server: MockRestServiceServer

    @BeforeEach
    fun setUp() {
        server = MockRestServiceServer.createServer(restTemplate)
        `when`(ticketRepo.findById("STUB-1")).thenReturn(
            Optional.of(StubTicket("STUB-1", "RUNNING", "stub-token", 1, 1))
        )
    }

    @Test
    fun `default callback target is gateway without localhost`() {
        server.expect(requestTo("http://gateway:80/ms/auth/api/external/auth/itsm/create_callback"))
            .andExpect(method(HttpMethod.POST))
            .andExpect(content().string(org.hamcrest.Matchers.containsString("\"sn\":\"STUB-1\"")))
            .andExpect(content().string(org.hamcrest.Matchers.containsString("\"approve_result\":\"true\"")))
            .andRespond(withSuccess("{\"code\":0}", APPLICATION_JSON))
        service.notifyApproval("STUB-1", true, "", "u1", "admin")
        server.verify()
        assertThat(true).isTrue()
    }

    @Test
    fun `explicit callback url takes precedence`() {
        server.expect(requestTo("http://other:9000/cb"))
            .andExpect(method(HttpMethod.POST))
            .andRespond(withSuccess("{\"code\":0}", APPLICATION_JSON))
        service.notifyApproval("STUB-1", false, "http://other:9000/cb", "u1", "admin")
        server.verify()
    }
}
