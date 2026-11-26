package com.tencent.bk.devops.iamstub.data

import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Component

@Component
class IdInitializer(private val jdbcTemplate: JdbcTemplate) : ApplicationRunner {
    override fun run(args: ApplicationArguments?) = initialize()

    fun initialize() {
        val max = listOf("stub_application", "stub_group", "stub_member")
            .mapNotNull { table ->
                jdbcTemplate.queryForObject("SELECT MAX(id) FROM \"$table\"", Long::class.java)?.toInt()
            }
            .maxOrNull() ?: 0
        Ids.advanceTo(max)
    }
}
