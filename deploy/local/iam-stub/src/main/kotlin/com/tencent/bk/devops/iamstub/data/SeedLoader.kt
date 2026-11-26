package com.tencent.bk.devops.iamstub.data

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.annotation.Value
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.jdbc.core.JdbcTemplate
import org.springframework.stereotype.Component
import java.io.File

@Component
class SeedLoader(
    @Value("\${stub.seed-path:}") private val seedPath: String,
    private val objectMapper: ObjectMapper,
    private val jdbcTemplate: JdbcTemplate,
    private val gradeManagerRepo: GradeManagerRepo,
    private val groupRepo: GroupRepo
) : ApplicationRunner {

    private val logger = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments?) {
        seed()
    }

    fun run() = run(null)

    fun seed() {
        if (gradeManagerRepo.count() > 0) {
            logger.info("stub seed already present, skipping")
            return
        }
        val dir = if (seedPath.isBlank()) null else File(seedPath)
        val groups = if (dir != null && dir.isDirectory) {
            try {
                parseGroups(dir)
            } catch (e: Exception) {
                logger.warn("failed to parse seed path $seedPath, using built-in seed", e)
                emptyList()
            }
        } else emptyList()

        jdbcTemplate.update(
            "MERGE INTO \"stub_grade_manager\" (id, name, project) KEY(id) VALUES (?, ?, ?)",
            1001, "stub-manager", "stub-demo"
        )
        val seedGroups = groups.ifEmpty {
            listOf(
                StubGroup(10001, "stub-group-1", "stub group 1", "stub-demo"),
                StubGroup(10002, "stub-group-2", "stub group 2", "stub-demo")
            )
        }
        seedGroups.forEach { g ->
            jdbcTemplate.update(
                "MERGE INTO \"stub_group\" (id, name, description, project) KEY(id) VALUES (?, ?, ?, ?)",
                g.id, g.name, g.description, g.project
            )
        }
        if (groups.isEmpty()) {
            listOf(10001 to "demo", 10002 to "demo").forEach { (gid, user) ->
                jdbcTemplate.update(
                    "INSERT INTO \"stub_member\" (group_id, type, member_id, expired_at) VALUES (?, ?, ?, ?)",
                    gid, "USER", user, 0
                )
            }
        }
        logger.info("stub seed complete: groups=${groupRepo.count()}")
    }

    private fun parseGroups(dir: File): List<StubGroup> {
        val result = mutableListOf<StubGroup>()
        dir.listFiles { f -> f.name.startsWith("0003") && f.endsWith(".json") }
            ?.sorted()
            ?.forEach { file ->
                val root: JsonNode = objectMapper.readTree(file)
                root.path("operations").forEach { op ->
                    if (op.path("operation").asText() == "upsert_resource_type") {
                        val data = op.path("data")
                        val id = data.path("id").asText("resource")
                        result.add(
                            StubGroup(
                                id = 10001 + result.size,
                                name = data.path("name").asText(id),
                                description = data.path("name_en").asText(id),
                                project = "stub-demo"
                            )
                        )
                    }
                }
            }
        return result.take(2)
    }
}
