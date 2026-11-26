package com.tencent.bk.devops.iamstub.data

import org.springframework.data.repository.CrudRepository

interface GroupRepo : CrudRepository<StubGroup, Int>
interface MemberRepo : CrudRepository<StubMember, Long>
interface ApplicationRepo : CrudRepository<StubApplication, Int>
interface GradeManagerRepo : CrudRepository<StubGradeManager, Int>
interface TicketRepo : CrudRepository<StubTicket, String>
