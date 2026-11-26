package com.tencent.bk.devops.iamstub.data

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.test.context.ActiveProfiles

@SpringBootTest
@ActiveProfiles("test")
class SeedLoaderTest @Autowired constructor(
    val groupRepo: GroupRepo,
    val gradeManagerRepo: GradeManagerRepo,
    val seedLoader: SeedLoader
) {
    @Test
    fun `seed produces non-empty groups and deterministic sn`() {
        assertThat(groupRepo.count() >= 2).isTrue()
        assertThat(gradeManagerRepo.findById(1001)).isPresent
        val n = Ids.next()
        assertThat(snOf(n)).isEqualTo("STUB-$n")
    }

    @Test
    fun `seed is idempotent`() {
        val before = groupRepo.count()
        seedLoader.run()
        assertThat(groupRepo.count()).isEqualTo(before)
    }
}
