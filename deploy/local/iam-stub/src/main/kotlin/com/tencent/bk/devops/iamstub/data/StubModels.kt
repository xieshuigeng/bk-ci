package com.tencent.bk.devops.iamstub.data

import org.springframework.data.annotation.Id
import org.springframework.data.relational.core.mapping.Table
import java.util.concurrent.atomic.AtomicInteger

@Table("stub_grade_manager")
data class StubGradeManager(
    @Id val id: Int,
    val name: String,
    val project: String
)

@Table("stub_group")
data class StubGroup(
    @Id val id: Int,
    val name: String,
    val description: String,
    val project: String
)

@Table("stub_member")
data class StubMember(
    @Id val id: Long? = null,
    val groupId: Int,
    val type: String,
    val memberId: String,
    val expiredAt: Long
)

@Table("stub_application")
data class StubApplication(
    @Id val id: Int? = null,
    val sn: String,
    val groupIds: String,
    val applicant: String,
    val status: String,
    val callbackId: Int,
    val approveResult: String? = null
)

@Table("stub_ticket")
data class StubTicket(
    @Id val sn: String,
    val status: String,
    val token: String,
    val callbackId: Int,
    val applyId: Int
)

object Ids {
    private val counter = AtomicInteger(0)
    fun next(): Int = counter.incrementAndGet()
}

fun snOf(n: Int): String = "STUB-$n"
