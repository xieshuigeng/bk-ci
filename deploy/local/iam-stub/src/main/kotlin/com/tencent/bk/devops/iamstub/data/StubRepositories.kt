package com.tencent.bk.devops.iamstub.data

import org.springframework.data.repository.CrudRepository

interface GroupRepo : CrudRepository<StubGroup, Int>

interface MemberRepo : CrudRepository<StubMember, Long> {
    fun findByGroupId(groupId: Int): List<StubMember>
    fun findByGroupIdAndMemberId(groupId: Int, memberId: String): List<StubMember>
}

interface ApplicationRepo : CrudRepository<StubApplication, Int> {
    fun findByStatus(status: String): List<StubApplication>
}

interface GradeManagerRepo : CrudRepository<StubGradeManager, Int>

interface TicketRepo : CrudRepository<StubTicket, String> {
    fun findByCallbackId(callbackId: Int): List<StubTicket>
}
