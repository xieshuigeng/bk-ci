package com.tencent.bk.devops.iamstub.data

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.test.context.ActiveProfiles

@SpringBootTest
@ActiveProfiles("test")
class IdInitializerTest @Autowired constructor(val initializer: IdInitializer, val jdbcTemplate: JdbcTemplate) {
    @Test
    fun `counter advances past persisted ids after restart`() {
        val high = Ids.next() + 100
        jdbcTemplate.update(
            "INSERT INTO \"stub_application\" (id, sn, group_ids, applicant, status, callback_id) VALUES (?, ?, ?, ?, ?, ?)",
            high, "STUB-RESTART-$high", "", "u", "PENDING", high
        )
        initializer.initialize()
        assertThat(Ids.next() > high).isTrue()
    }
}
