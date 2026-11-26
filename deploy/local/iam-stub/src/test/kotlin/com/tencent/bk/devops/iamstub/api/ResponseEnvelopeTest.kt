package com.tencent.bk.devops.iamstub.api

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test

class ResponseEnvelopeTest {
    private val mapper = jacksonObjectMapper()

    @Test
    fun `envelope has numeric code and exact fields`() {
        val json = mapper.writeValueAsString(ResponseEnvelope(data = "payload"))
        assertThat(json).contains("\"code\":0")
        assertThat(json).contains("\"message\":\"OK\"")
        assertThat(json).contains("\"result\":true")
        assertThat(json).contains("\"data\":\"payload\"")
    }
}
