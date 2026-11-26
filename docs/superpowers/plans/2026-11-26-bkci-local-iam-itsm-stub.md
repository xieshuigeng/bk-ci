# 本地 IAM/ITSM 协议兼容桩 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `deploy/local/iam-stub/` 建一个独立 Kotlin + Spring Boot 桩服务，让本地 bk-ci 以 `auth.idProvider=rbac` 跑通「IAM 用户组申请」与「ITSM 项目审批」两条最小闭环，权限中心两个 iframe 页显示真实数据且可操作。

**Architecture:** 一个独立 Gradle build 的 Spring Boot 服务，同时暴露 IAM SDK API、ITSM API 与两个最简 HTML 页面；H2 文件库存桩自身状态，不写 `devops_ci_auth`（除一次性 setup SQL）；bk-ci 只通过本地配置指向桩，业务代码零改动。

**Tech Stack:** Kotlin 1.9.24, Java 17, Spring Boot 3.4.0, Spring Web + Spring Data JDBC + H2, Jackson, JUnit 5 + MockMvc + MockRestServiceServer, Gradle 8.10.2（复用仓库 wrapper）

**Spec:** `docs/superpowers/specs/2026-11-25-bkci-local-iam-itsm-stub-design.md`

## Global Constraints

- Java 17；Gradle 8.10.2（`src/backend/ci/gradle/wrapper`，首次构建需联网下载发行版与依赖，Maven Central 已验证可达）。
- 独立 Gradle build：`deploy/local/iam-stub/` 自带 `settings.gradle.kts`；**禁止**注册进 `src/backend/ci/settings.gradle.kts`。
- IAM 响应信封：`{"code":0,"message":"OK","result":true,"data":...}`；`code` 必须是 **JSON 数值** 0（SDK 调用 `Long.longValue()`），不能是字符串。
- 系统 ID 固定 `bk_ci_rbac`；app code `bk_ci`；app secret 用本地已有值 `c28aee9ca65c1719d168bdc8de6b1d77`（本地开发值，不新增凭据）。
- 回调地址默认 `http://gateway:80`（容器网内可达）；**禁止**硬编码 `http://localhost:8080`。
- `sn = STUB-<递增整数>`；`callbackId` 与该整数同值；`role_id` 取 grade manager id。
- 取消类接口 message：`PUT .../applications/{callbackId}/cancel/` 必须 `"OK"`；ITSM `POST /operate_ticket/` 必须 `"success"`。
- 更新子集管理员是 `POST /.../subset_managers/{id}`（**无尾斜杠**），不是 PUT。
- 桩服务运行时绝不写 `devops_ci_auth`；仅允许 `setup-local-auth.sql` 一次性预置。
- 提交前 `git diff --check` 干净；只推 `mine master`，**绝不推 `origin`**。

## Review Focus

以下是 spec 暗示但任务测试最容易漏掉、且错了会真正坏掉本地联调的输入/条件。每条都指定了归属任务的钉死测试。

1. `code` 被序列化成字符串 `"0"` → SDK 抛 `IamException`。Task 1 测试断言 JSON 中 `code` 为数值 0。
2. 更新子集管理员用 PUT 或带尾斜杠 → SDK 404。Task 4 测试用 `post("/.../subset_managers/2001")` 断言 200。
3. `belong` 判定与 `members` 列表不一致 → 成员同步判成功却落不了库。Task 4 测试断言审批后 `belong=true` 且 `/groups/{id}/members/` 含同一成员。
4. 回调地址取到 `http://localhost:8080` → 桩容器内不可达，审批链断。Task 6 测试用 MockRestServiceServer 断言实际请求 URL 以 `http://gateway:80` 开头。
5. `sn`/`callbackId`/`role_id` 形状或取值错 → bk-ci 按 sn 查不到回调行。Task 5 测试断言 `{id,sn}`、`{id,role_id}` 三字段精确值。

## 本计划不实现（来自 spec 的有意排除）

- IAM 迁移接口（`/api/v2/open/migration/bkci/*`）：本地不触发迁移链路，spec 已标为「默认返回 ok 壳，按需再补」；`BK_CI_IAM_MIGRATE_TOKEN` 仅占位配置。
- SSO / ESB / 登录桩：spec 列为风险项，超出本次范围；若本地 `rbac` 启动因这些依赖报错，记录后再单独立项。

---

### Task 1: 独立 Gradle 骨架与 IAM 信封契约

**Files:**
- Create: `deploy/local/iam-stub/settings.gradle.kts`
- Create: `deploy/local/iam-stub/build.gradle.kts`
- Create: `deploy/local/iam-stub/src/main/resources/application.yml`
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/api/ResponseEnvelope.kt`
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/IamStubApplication.kt`
- Test: `deploy/local/iam-stub/src/test/kotlin/com/tencent/bk/devops/iamstub/api/ResponseEnvelopeTest.kt`

**Interfaces:**
- Consumes: 无（首任务）。
- Produces: `data class ResponseEnvelope<T>(val code: Long = 0, val message: String = "OK", val result: Boolean = true, val data: T? = null)`；Jackson 序列化字段名 `code,message,result,data`，`code` 为 JSON 数值。所有后续 controller 返回 `ResponseEnvelope<T>`。
- Produces: `ResponseEnvelope.Companion.ok<T>(data: T): ResponseEnvelope<T>` 工厂方法（message 用默认值 `"OK"`），供 Task 4/5/6 使用；需要非 OK message 时直接用构造函数，如 `ResponseEnvelope(message = "success", data = null)`。
- Produces: `IamStubApplication`（`@SpringBootApplication`），供后续 `@SpringBootTest` 使用。
- Produces: 构建命令 `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test`（工作目录为仓库根 `/home/xiesg/test/bk-ci`）。

- [x] **Step 1: 写失败测试**

`ResponseEnvelopeTest.kt`：
```kotlin
class ResponseEnvelopeTest {
    private val mapper = jacksonObjectMapper()

    @Test
    fun `envelope has numeric code and exact fields`() {
        val json = mapper.writeValueAsString(ResponseEnvelope("payload"))
        assertThat(json).contains("\"code\":0")
        assertThat(json).contains("\"message\":\"OK\"")
        assertThat(json).contains("\"result\":true")
        assertThat(json).contains("\"data\":\"payload\"")
    }
}
```
（`jacksonObjectMapper()` 来自 `com.fasterxml.jackson.module.kotlin.jacksonObjectMapper`，`assertThat` 来自 AssertJ。）

- [x] **Step 2: 跑测试确认失败**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*ResponseEnvelopeTest'`
Expected: FAIL，`Unresolved reference: ResponseEnvelope` 或构建配置缺失。

- [x] **Step 3: 实现骨架与信封**

`settings.gradle.kts`：`rootProject.name = "bkci-local-iam-stub"`。
`build.gradle.kts`：`plugins` 用 `kotlin("jvm") version "1.9.24"`、`org.springframework.boot version "3.4.0"`、`io.spring.dependency-management version "1.1.6"`；`repositories { mavenCentral() }`；依赖 `spring-boot-starter-web`、`spring-boot-starter-data-jdbc`、`runtimeOnly("com.h2database:h2")`、`testImplementation("org.springframework.boot:spring-boot-starter-test")`；`kotlin { jvmToolchain(17) }`。
`application.yml`：
```yaml
server:
  port: 8080
spring:
  datasource:
    url: jdbc:h2:file:./data/iam-stub;AUTO_SERVER=TRUE
    driver-class-name: org.h2.Driver
    username: sa
    password:
  sql:
    init:
      mode: always
stub:
  system-id: bk_ci_rbac
  callback-base-url: ${BKCI_CALLBACK_BASE_URL:http://gateway:80}
  seed-path: ${STUB_SEED_PATH:}
```
`ResponseEnvelope.kt` 与 `IamStubApplication.kt` 按签名实现，`ResponseEnvelope` 带 `companion object { fun <T> ok(data: T): ResponseEnvelope<T> = ResponseEnvelope(data = data) }`。

- [x] **Step 4: 跑测试确认通过**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*ResponseEnvelopeTest'`
Expected: PASS。

- [x] **Step 5: 提交**

```bash
git add deploy/local/iam-stub
git commit -m "feat(iam-stub): bootstrap independent Gradle build and response envelope"
```

---

### Task 2: H2 数据层、实体与种子

**Files:**
- Create: `deploy/local/iam-stub/src/main/resources/schema.sql`
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/data/StubModels.kt`
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/data/StubRepositories.kt`
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/data/SeedLoader.kt`
- Test: `deploy/local/iam-stub/src/test/kotlin/com/tencent/bk/devops/iamstub/data/SeedLoaderTest.kt`

**Interfaces:**
- Consumes: `IamStubApplication`（Task 1）、`ResponseEnvelope`（Task 1）。
- Produces: `StubGroup(@Id val id: Int, val name: String, val description: String, val project: String)`、`StubMember(@Id val id: Long? = null, val groupId: Int, val type: String, val memberId: String, val expiredAt: Long)`、`StubApplication(@Id val id: Int? = null, val sn: String, val groupIds: String, val applicant: String, val status: String, val callbackId: Int, val approveResult: String?)`、`StubGradeManager(@Id val id: Int, val name: String, val project: String)`、`StubTicket(@Id val sn: String, val status: String, val token: String, val callbackId: Int, val applyId: Int)`。
- Produces: `StubRepositories.kt` 暴露 Spring Data JDBC 接口 `GroupRepo`、`MemberRepo`、`ApplicationRepo`、`GradeManagerRepo`、`TicketRepo`，各自继承 `CrudRepository<T, ID>`。
- Produces: `object Ids { fun next(): Int }`（`AtomicInteger` 从 1 起）；`fun snOf(n: Int) = "STUB-$n"`。
- Produces: `class SeedLoader(@Value("\${stub.seed-path}") private val seedPath: String, ...)`：`ApplicationRunner`，若 `seedPath` 非空且目录存在则从 `0003~0007*.json` 解析出 grade manager / group 种子，否则用内置示例（1 个 grade manager id=1001、2 个 group id=10001/10002、2 个 member）。种子必须幂等。

- [x] **Step 1: 写失败测试**

`SeedLoaderTest.kt`（`@SpringBootTest` + `@ActiveProfiles("test")`，测试用 H2 内存库覆盖 datasource url）：
```kotlin
@Test
fun `seed produces non-empty groups and deterministic sn`() {
    assertThat(groupRepo.count()).isGreaterThanOrEqual(2)
    assertThat(gradeManagerRepo.findById(1001)).isPresent
    val n = Ids.next()
    assertThat(snOf(n)).isEqualTo("STUB-$n")
}
```
另加幂等测试：重复调用 `seedLoader.run()` 后 `groupRepo.count()` 不变。

- [x] **Step 2: 跑测试确认失败**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*SeedLoaderTest'`
Expected: FAIL，`Unresolved reference: SeedLoader` 或 `groupRepo` 未定义。

- [x] **Step 3: 实现 schema、实体、Repository、SeedLoader**

`schema.sql` 建 5 张表：`stub_grade_manager(id INT PK, name, project)`、`stub_group(id INT PK, name, description, project)`、`stub_member(id BIGINT AUTO_INCREMENT PK, group_id INT, type VARCHAR(32), member_id VARCHAR(255), expired_at BIGINT)`、`stub_application(id INT AUTO_INCREMENT PK, sn VARCHAR(64), group_ids VARCHAR(512), applicant VARCHAR(255), status VARCHAR(32), callback_id INT, approve_result VARCHAR(16))`、`stub_ticket(sn VARCHAR(64) PK, status VARCHAR(32), token VARCHAR(64), callback_id INT, apply_id INT)`。全部 `CREATE TABLE IF NOT EXISTS`。
`SeedLoader` 用 Jackson `ObjectMapper` 读目录，JSON 里取 `operations[].operation` 与 `data.id/name`；解析失败时降级到内置示例并打日志，不让启动失败。

- [x] **Step 4: 跑测试确认通过**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*SeedLoaderTest'`
Expected: PASS（含幂等测试）。

- [x] **Step 5: 提交**

```bash
git add deploy/local/iam-stub/src
git commit -m "feat(iam-stub): add H2 state, repositories and idempotent seed"
```

---

### Task 3: IAM 基础与策略接口

**Files:**
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/api/IamBasicController.kt`
- Test: `deploy/local/iam-stub/src/test/kotlin/com/tencent/bk/devops/iamstub/api/IamBasicControllerTest.kt`

**Interfaces:**
- Consumes: `ResponseEnvelope`（Task 1）。
- Produces: `IamBasicController` 的 5 个端点：
  - `GET /api/v1/model/systems/{system}/token` → `ResponseEnvelope<Map<String,String>>`，`data={"token":"stub-token"}`
  - `GET /api/v1/model/systems/{system}/query` → `ResponseEnvelope<Map<String,Any>>`，含 `base_info,resource_types,actions,instance_selections,action_groups`
  - `POST /api/v2/policy/systems/{system}/auth/` → `data={"allowed":true}`
  - `POST /api/v2/policy/systems/{system}/auth_by_actions/` → `data={"<actionId>":true}`
  - `POST /api/v2/policy/systems/{system}/query/` → `data={"op":"AND","content":[]}`
- 所有端点忽略请求体具体内容，只按路径返回；`x-bkapi-authorization` 头不强制校验（桩简化）。

- [x] **Step 1: 写失败测试**

`@WebMvcTest(IamBasicController::class)` + MockMvc，一个测试覆盖 5 个端点，断言：
```kotlin
mockMvc.perform(get("/api/v1/model/systems/bk_ci_rbac/token"))
    .andExpect(status().isOk)
    .andExpect(jsonPath("$.code").value(0))
    .andExpect(jsonPath("$.data.token").value("stub-token"))
mockMvc.perform(post("/api/v2/policy/systems/bk_ci_rbac/auth/")
    .contentType(APPLICATION_JSON).content("{}"))
    .andExpect(jsonPath("$.data.allowed").value(true))
mockMvc.perform(post("/api/v2/policy/systems/bk_ci_rbac/query/")
    .contentType(APPLICATION_JSON).content("{}"))
    .andExpect(jsonPath("$.data.op").value("AND"))
```

- [x] **Step 2: 跑测试确认失败**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*IamBasicControllerTest'`
Expected: FAIL，404 或类未定义。

- [x] **Step 3: 实现 `IamBasicController`**

按 Interfaces 中的路径与返回形状实现，`@RestController`。`code` 必须来自 Task 1 的 `ResponseEnvelope` 默认值（数值 0，禁止手拼字符串）。

- [x] **Step 4: 跑测试确认通过**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*IamBasicControllerTest'`
Expected: PASS。

- [x] **Step 5: 提交**

```bash
git add deploy/local/iam-stub/src
git commit -m "feat(iam-stub): implement IAM token and policy endpoints"
```

---

### Task 4: IAM V2 management（管理员 / 组 / 成员 / 归属）

**Files:**
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/api/IamManagementController.kt`
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/service/GroupStateService.kt`
- Test: `deploy/local/iam-stub/src/test/kotlin/com/tencent/bk/devops/iamstub/api/IamManagementControllerTest.kt`

**Interfaces:**
- Consumes: `ResponseEnvelope`（Task 1）、`GroupRepo`/`MemberRepo`/`GradeManagerRepo`、`Ids`（Task 2）。
- Produces: `class GroupStateService(...)`，方法：
  - `fun createGroup(gradeManagerId: Int, body: Map<String,Any>): List<Int>`（写 `stub_group`，返回 id 列表）
  - `fun addMember(groupId: Int, body: Map<String,Any>)`（写 `stub_member`）
  - `fun memberBelongs(userId: String, groupId: Int): Boolean`
  - `fun listMembers(groupId: Int): List<StubMember>`
  - `fun detailOf(groupId: Int): Map<String,Any>`（字段 `id,name,description,readonly,user_count,department_count,subject_template_count,joined,apply_disable`）
- Produces: `IamManagementController` 端点（全部前缀 `/api/v2/open/management/systems/{system}`）：
  - `POST /grade_managers/` → `{"id":<int>}`；`GET/PUT/DELETE /grade_managers/{id}[/]`
  - `GET /grade_managers/{id}/groups/?page_size=&page=` → `{"count":n,"results":[detailOf]}`；`POST /grade_managers/{id}/groups/` → `[<int>]`
  - `POST /grade_managers/{id}/subset_managers/` → `{"id":<int>}`；`GET/POST /subset_managers/{id}`（**POST 无尾斜杠**）；`DELETE /subset_managers/{id}/`
  - `GET /subset_managers/{id}/groups/` → 同组列表
  - `PUT/DELETE /groups/{groupId}/`；`GET/POST /groups/{groupId}/policies/`；`GET /groups/{groupId}/policies/-/actions/`
  - `GET/POST/DELETE /groups/{groupId}/members/[?type=&ids=]`；`PUT /groups/{groupId}/members/-/expired_at/`
  - `GET /users/{userId}/groups/belong/?group_ids=<csv>` → `{"<gid>":{"belong":true,"expired_at":0,"created_at":0,"is_direct_added":true}}`
  - `GET /departments/{deptId}/groups/belong/?group_ids=<csv>` → 同上
  - `GET /group_member_types/{type}/members/{memberId}/groups/-/details/?group_ids=<csv>` → `[{"id","name","description","created_at","expired_at"}]`
  - `GET /grade_managers/{id}/subject_templates/`、`GET /groups/{groupId}/subject_templates/` → `{"count":0,"results":[]}`
  - `POST /grade_managers/-/applications/`、`POST /grade_managers/{id}/applications/`、`POST /groups/-/renew/applications/` → 交由 Task 5 的 `IamApplicationController` 处理，本任务不实现这些路径。

- [x] **Step 1: 写失败测试**

`@WebMvcTest(IamManagementController::class)` + MockMvc（mock `GroupStateService`），三个测试：
```kotlin
@Test fun `group list has count and results`() {
    mockMvc.perform(get("/api/v2/open/management/systems/bk_ci_rbac/grade_managers/1001/groups/?page=1&page_size=10"))
        .andExpect(jsonPath("$.code").value(0))
        .andExpect(jsonPath("$.data.count").isNumber)
        .andExpect(jsonPath("$.data.results").isArray)
}
@Test fun `update subset manager is POST without trailing slash`() {
    mockMvc.perform(post("/api/v2/open/management/systems/bk_ci_rbac/subset_managers/2001")
        .contentType(APPLICATION_JSON).content("{}"))
        .andExpect(status().isOk)
        .andExpect(jsonPath("$.code").value(0))
}
@Test fun `belong and members agree after add`() {
    // 先 POST members 加用户 u1 到组 10001，再断言 belong 为 true 且 members 含 u1
    mockMvc.perform(post("/api/v2/open/management/systems/bk_ci_rbac/groups/10001/members/")
        .contentType(APPLICATION_JSON).content("{\"members\":[{\"type\":\"USER\",\"id\":\"u1\"}],\"expired_at\":0}"))
        .andExpect(status().isOk)
    mockMvc.perform(get("/api/v2/open/management/systems/bk_ci_rbac/users/u1/groups/belong/?group_ids=10001"))
        .andExpect(jsonPath("$.data['10001'].belong").value(true))
    mockMvc.perform(get("/api/v2/open/management/systems/bk_ci_rbac/groups/10001/members/"))
        .andExpect(jsonPath("$.data.results[*].id").value(hasItem("u1")))
}
```
（`hasItem` 来自 `org.hamcrest.Matchers.hasItem`。第三个测试不能用纯 `@WebMvcTest` mock service，改用 `@SpringBootTest` + MockMvc + 真实 `GroupStateService` + H2 内存库。）

- [x] **Step 2: 跑测试确认失败**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*IamManagementControllerTest'`
Expected: FAIL，404 或 bean 未定义。

- [x] **Step 3: 实现 `GroupStateService` 与 `IamManagementController`**

`GroupStateService` 用 Task 2 的 Repository 做读写；`addMember` 写 `memberId` 且 `expiredAt` 存传入值或 0；`memberBelongs` 查 `stub_member`。Controller 用 `@RequestMapping` 收敛前缀，`@GetMapping`/`@PostMapping`/`@PutMapping`/`@DeleteMapping` 按 Interfaces 逐条映射，返回 `ResponseEnvelope.ok(data)`（或 Task 1 的构造函数）。组列表分页参数用 `@RequestParam(required=false)` 接收但当前忽略过滤。

- [x] **Step 4: 跑测试确认通过**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*IamManagementControllerTest'`
Expected: PASS（含 POST 无尾斜杠与 belong/members 一致两个钉死测试）。

- [x] **Step 5: 提交**

```bash
git add deploy/local/iam-stub/src
git commit -m "feat(iam-stub): implement IAM management, members and belong APIs"
```

---

### Task 5: IAM 申请与审批接口（两条链的起点）

**Files:**
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/service/ApplicationService.kt`
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/api/IamApplicationController.kt`
- Test: `deploy/local/iam-stub/src/test/kotlin/com/tencent/bk/devops/iamstub/api/IamApplicationControllerTest.kt`

**Interfaces:**
- Consumes: `ResponseEnvelope`（Task 1）、`ApplicationRepo`/`TicketRepo`/`Ids`/`snOf`（Task 2）、`GroupStateService.addMember`（Task 4）。
- Produces: `class ApplicationService(...)`：
  - `fun createGroupApplication(body: Map<String,Any>): List<Int>`
  - `fun createGradeManagerApplication(body: Map<String,Any>): Pair<Int,String>`（返回 `id to sn`）
  - `fun approve(callbackId: Int, body: Map<String,Any>): Pair<Int,Int>`（返回 `id to roleId`，`roleId` 取对应 grade manager id；同时把成员写入 group、把 ticket/application 置为通过）
  - `fun cancel(callbackId: Int): Boolean`
- Produces: `IamApplicationController` 端点（前缀同 Task 4）：
  - `POST /groups/-/applications/` → `data={"ids":[n]}`
  - `POST /grade_managers/-/applications/` 与 `POST /grade_managers/{id}/applications/` → `data={"id":n,"sn":"STUB-n"}`
  - `POST /applications/{callbackId}/approve/` → `data={"id":n,"role_id":m}`
  - `PUT /applications/{callbackId}/cancel/` → `ResponseEnvelope(message="OK", data=null)`
  - `POST /groups/-/renew/applications/` → `data={}`
- 本任务**不触发** ITSM 回调；回调编排在 Task 6。

- [x] **Step 1: 写失败测试**

`@SpringBootTest` + MockMvc + H2 内存库，两个测试：
```kotlin
@Test fun `grade manager application returns exact id and sn`() {
    mockMvc.perform(post("/api/v2/open/management/systems/bk_ci_rbac/grade_managers/-/applications/")
        .contentType(APPLICATION_JSON).content("{\"name\":\"p\",\"callback_id\":\"cb-1\"}"))
        .andExpect(jsonPath("$.code").value(0))
        .andExpect(jsonPath("$.data.id").isNumber)
        .andExpect(jsonPath("$.data.sn").value(matchesPattern("STUB-\\d+")))
}
@Test fun `approve returns id and role_id and cancel message is OK`() {
    val sn = "STUB-9"
    mockMvc.perform(post("/api/v2/open/management/systems/bk_ci_rbac/applications/9/approve/")
        .contentType(APPLICATION_JSON).content("{\"sn\":\"$sn\",\"approve_result\":true}"))
        .andExpect(jsonPath("$.data.id").value(9))
        .andExpect(jsonPath("$.data.role_id").value(1001))
    mockMvc.perform(put("/api/v2/open/management/systems/bk_ci_rbac/applications/9/cancel/"))
        .andExpect(jsonPath("$.message").value("OK"))
}
```
另加用户组申请测试：`POST /groups/-/applications/` 返回 `data.ids` 为数组且元素为数值。

- [x] **Step 2: 跑测试确认失败**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*IamApplicationControllerTest'`
Expected: FAIL，404 或 bean 未定义。

- [x] **Step 3: 实现 `ApplicationService` 与 `IamApplicationController`**

`createGradeManagerApplication` 用 `Ids.next()` 分配 id/callbackId，`snOf(n)` 生成 sn，写 `stub_ticket`（status=RUNNING，token 固定 `stub-token`）与 `stub_application`。`approve` 按 callbackId 查 ticket/application，调 `GroupStateService.addMember` 写入申请人，更新 status=APPROVED，`role_id` 返回 1001（种子 grade manager id）。`cancel` 更新 status=CANCELLED 并返回 `message="OK"` 的信封。

- [x] **Step 4: 跑测试确认通过**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*IamApplicationControllerTest'`
Expected: PASS。

- [x] **Step 5: 提交**

```bash
git add deploy/local/iam-stub/src
git commit -m "feat(iam-stub): implement application create, approve and cancel"
```

---

### Task 6: ITSM API 与回调编排

**Files:**
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/api/ItsmController.kt`
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/service/ItsmCallbackService.kt`
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/api/StubApprovalController.kt`
- Test: `deploy/local/iam-stub/src/test/kotlin/com/tencent/bk/devops/iamstub/api/ItsmControllerTest.kt`
- Test: `deploy/local/iam-stub/src/test/kotlin/com/tencent/bk/devops/iamstub/service/ItsmCallbackServiceTest.kt`

**Interfaces:**
- Consumes: `ResponseEnvelope`（Task 1）、`TicketRepo`/`ApplicationRepo`（Task 2）、`ApplicationService.approve`（Task 5）、配置 `stub.callback-base-url`（Task 1）。
- Produces: `ItsmController` 端点：
  - `POST /token/verify/` → `data={"is_passed":true}`（不校验具体 token）
  - `GET /get_ticket_status?sn=<sn>` → `data={"current_status":"FINISHED"|"RUNNING"}`（按 `stub_ticket.status`）
  - `POST /operate_ticket/` → `ResponseEnvelope(message="success", data=null)`
- Produces: `class ItsmCallbackService(private val restTemplate: RestTemplate, @Value("\${stub.callback-base-url}") private val baseUrl: String, ...)`：
  - `fun notifyApproval(sn: String, approved: Boolean, callbackUrl: String?, applicant: String, lastApprover: String)`
  - 目标 URL = `callbackUrl?.takeIf { it.isNotBlank() } ?: "$baseUrl/ms/auth/api/external/auth/itsm/" + (if (approved) "create_callback" else "update_callback")`；**禁止**拼接 `localhost`。
  - body 字段：`title,current_status,sn,ticket_url,update_at,updated_by,approve_result("true"/"false"),token,last_approver`。
  - `token` 取 `stub_ticket.token`（与 `/token/verify/` 一致）。
- Produces: `StubApprovalController`：
  - `POST /itsm-stub/api/approve`（body `{"sn":"STUB-n","approved":true,"callbackUrl":""|null}`）→ 查 ticket 得 callbackId → `applicationService.approve(callbackId, mapOf("sn" to sn))` → `itsmCallbackService.notifyApproval(...)` → `data={"ok":true}`
  - `POST /stub/api/approve-group`（body `{"id":n,"approved":true}`）→ `applicationService.approve(n, ...)` → `data={"ok":true}`（用户组链，不回调 ITSM）

- [x] **Step 1: 写失败测试**

`ItsmControllerTest`（`@WebMvcTest`）：
```kotlin
mockMvc.perform(post("/token/verify/").contentType(APPLICATION_JSON).content("{\"token\":\"stub-token\"}"))
    .andExpect(jsonPath("$.code").value(0))
    .andExpect(jsonPath("$.data.is_passed").value(true))
mockMvc.perform(post("/operate_ticket/").contentType(APPLICATION_JSON).content("{}"))
    .andExpect(jsonPath("$.message").value("success"))
```
`ItsmCallbackServiceTest`（用 `MockRestServiceServer`）：
```kotlin
val server = MockRestServiceServer.createServer(restTemplate)
server.expect(requestTo("http://gateway:80/ms/auth/api/external/auth/itsm/create_callback"))
    .andExpect(method(HttpMethod.POST))
    .andExpect(content().string(containsString("\"sn\":\"STUB-1\"")))
    .andExpect(content().string(containsString("\"approve_result\":\"true\"")))
    .andRespond(withSuccess("{\"code\":0}", APPLICATION_JSON))
service.notifyApproval("STUB-1", true, "", "u1", "admin")
server.verify()
```
另加测试：传入 `callbackUrl="http://other:9000/cb"` 时请求打到该地址（覆盖优先级）。

- [x] **Step 2: 跑测试确认失败**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*Itsm*Test'`
Expected: FAIL，类或端点未定义。

- [x] **Step 3: 实现 ITSM 控制器、回调服务与审批编排端点**

`ItsmCallbackService` 用注入的 `RestTemplate`（在配置类里声明 bean）；`notifyApproval` 用 `postForEntity`，body 用 `Map<String,Any>` 交给 Jackson。`StubApprovalController` 按 Interfaces 编排，回调失败时记录日志但不让接口 500（桩要可重复点）。

- [x] **Step 4: 跑测试确认通过**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*Itsm*Test'`
Expected: PASS（含 gateway 地址钉死测试）。

- [x] **Step 5: 提交**

```bash
git add deploy/local/iam-stub/src
git commit -m "feat(iam-stub): implement ITSM endpoints and callback orchestration"
```

---

### Task 7: 两个 iframe HTML 页面

**Files:**
- Create: `deploy/local/iam-stub/src/main/kotlin/com/tencent/bk/devops/iamstub/api/IframePageController.kt`
- Test: `deploy/local/iam-stub/src/test/kotlin/com/tencent/bk/devops/iamstub/api/IframePageControllerTest.kt`

**Interfaces:**
- Consumes: `ApplicationRepo`/`TicketRepo`（Task 2）、Task 6 的两个审批端点。
- Produces: `IframePageController`：
  - `GET /iam-stub/apply`（produces `text/html;charset=UTF-8`）→ HTML 列出 `stub_application` 中 status=PENDING 的单（sn、申请人、组），每行「通过」按钮调用 `POST /stub/api/approve-group`，「驳回」按钮调用同端点 `approved=false`。
  - `GET /itsm-stub/` 与 `GET /itsm-stub/index.html`（produces `text/html;charset=UTF-8`）→ HTML 列出 `stub_ticket`（sn、status），每行按钮调用 `POST /itsm-stub/api/approve`。浏览器请求的 `#/ticket/approval-iframe` 是 fragment，不会发到服务端，所以服务端只需映射根路径。
  - 页面内联 `<script>` 用 `fetch` 调上述端点，成功后 `location.reload()`；内联 CSS，无外部资源。

- [x] **Step 1: 写失败测试**

`@SpringBootTest` + MockMvc + H2 内存库（先通过 `ApplicationService`/`TicketRepo` 插入一条 sn=`STUB-1` 的 pending 单）：
```kotlin
mockMvc.perform(get("/iam-stub/apply"))
    .andExpect(status().isOk)
    .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_HTML))
    .andExpect(content().string(containsString("STUB-1")))
    .andExpect(content().string(containsString("/stub/api/approve-group")))
mockMvc.perform(get("/itsm-stub/"))
    .andExpect(content().string(containsString("STUB-1")))
    .andExpect(content().string(containsString("/itsm-stub/api/approve")))
```

- [x] **Step 2: 跑测试确认失败**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*IframePageControllerTest'`
Expected: FAIL，404 或内容不含 sn。

- [x] **Step 3: 实现两个页面**

按 Interfaces 返回 HTML 字符串；对 sn 做 HTML 转义（防止种子数据含特殊字符破坏页面）。按钮用 `<button onclick="...">`，JS 用 `fetch` + JSON body。

- [x] **Step 4: 跑测试确认通过**

Run: `../../../src/backend/ci/gradlew -p deploy/local/iam-stub test --tests '*IframePageControllerTest'`
Expected: PASS。

- [x] **Step 5: 提交**

```bash
git add deploy/local/iam-stub/src
git commit -m "feat(iam-stub): add minimal iframe pages for apply and approval"
```

---

### Task 8: 本地部署接线与端到端验收

**Files:**
- Create: `deploy/local/iam-stub/Dockerfile`
- Create: `deploy/local/iam-stub/setup-local-auth.sql`
- Create: `deploy/local/iam-stub/verify-local.sh`
- Modify: `deploy/local/docker-compose.yml`
- Modify: `deploy/local/bkenv.properties`（仅尾部覆盖块）
- Modify: `deploy/local/README.md`

**Interfaces:**
- Consumes: Task 1–7 构建出的 fat jar（`bootJar`）。
- Produces: compose 服务 `iam-stub`：`build.context=../..`、`dockerfile=deploy/local/iam-stub/Dockerfile`、`image=bkci-local/iam-stub:local`、`container_name=bkci-iam-stub`、`networks=[bkci]`、`ports=["8081:8080"]`、`environment.BKCI_CALLBACK_BASE_URL=http://gateway:80`、`volumes=["iam-stub-data:/app/data"]`，并在文件尾声明卷 `iam-stub-data`。
- Produces: `bkenv.properties` 尾部覆盖块新增/改值：`BK_CI_AUTH_PROVIDER=rbac`、`BK_CI_IAM_APIGW_URL=http://iam-stub:8080`、`BK_CI_ITSM_APIGW_URL=http://iam-stub:8080`、`BK_CI_IAM_SYSTEM_ID=bk_ci_rbac`、`BK_CI_IAM_MIGRATE_TOKEN=stub-token`、`BK_CI_IAM_URL_PREFIX=http://localhost:8081/iam-stub`、`BK_CI_ITSM_URL_PREFIX=http://localhost:8081/itsm-stub`。
- Produces: `verify-local.sh`：curl 检查 4 件事——token 端点 code=0 且数值、组列表 count>0、两个页面 HTTP 200 且含 `STUB-`、ITSM token verify `is_passed=true`。

- [x] **Step 1: 写失败测试（验收脚本先写）**

`verify-local.sh` 按 Interfaces 写 4 个 curl 断言，每个失败都 `exit 1` 并打印具体 URL。此时脚本因桩未接线而失败。

- [x] **Step 2: 跑脚本确认失败**

Run: `bash deploy/local/iam-stub/verify-local.sh`
Expected: FAIL，连接被拒绝或字段不符。

- [x] **Step 3: 写 Dockerfile、setup SQL、compose 与配置**

`Dockerfile` 多阶段：
```dockerfile
FROM gradle:8.10.2-jdk17 AS build
WORKDIR /src
COPY src/backend/ci/gradlew /src/gradlew
COPY src/backend/ci/gradle/wrapper /src/gradle/wrapper
COPY deploy/local/iam-stub /src/iam-stub
COPY support-files/bkiam-rbac /src/support-files/bkiam-rbac
RUN chmod +x /src/gradlew && /src/gradlew -p /src/iam-stub --no-daemon bootJar

FROM eclipse-temurin:17-jre
COPY --from=build /src/iam-stub/build/libs/*.jar /app/iam-stub.jar
COPY --from=build /src/support-files/bkiam-rbac /app/support-files/bkiam-rbac
WORKDIR /app
EXPOSE 8080
ENV STUB_SEED_PATH=/app/support-files/bkiam-rbac
ENTRYPOINT ["java", "-jar", "iam-stub.jar"]
```
`setup-local-auth.sql`：插入测试项目 `stub-demo` 对应的 `T_AUTH_RESOURCE_GROUP` 行，`relation_id` 必须等于桩种子 group id `10001`；SQL 只写 `devops_ci_auth`，不写任何其它库，且用 `INSERT ... WHERE NOT EXISTS` 幂等。
`docker-compose.yml` 与 `bkenv.properties` 按 Interfaces 精确修改；`README.md` 说明「重建 frontend/auth 容器 → 执行 setup SQL → `docker compose up -d --build iam-stub` → 跑 verify-local.sh」。

- [x] **Step 4: 跑脚本确认通过并做静态检查**

Run:
```bash
docker compose -f deploy/local/docker-compose.yml config >/dev/null && echo COMPOSE_OK
docker compose -f deploy/local/docker-compose.yml up -d --build iam-stub
bash deploy/local/iam-stub/verify-local.sh
git diff --check
```
Expected: `COMPOSE_OK`；桩容器健康；验收脚本 4 项全 PASS；`git diff --check` 无输出。

- [x] **Step 5: 提交**

```bash
git add deploy/local/docker-compose.yml deploy/local/bkenv.properties deploy/local/README.md deploy/local/iam-stub
git commit -m "feat(local): wire iam-stub into local compose and config"
```

---

## 交付后的验证清单（不属于代码任务）

- 全量测试：`../../../src/backend/ci/gradlew -p deploy/local/iam-stub test`（所有 Task 的测试一起跑，PASS）。
- 链一手工验证：本地前端「申请权限」页提交加入 `10001` 组 → 「我的申请」页看到 `STUB-n` → 点通过 → 等待同步 → MySQL 查 `T_AUTH_RESOURCE_GROUP_MEMBER` 出现该用户，且 `T_AUTH_RESOURCE_GROUP_APPLY.STATUS='SUCCEED'`。
- 链二手工验证：本地创建项目 → 「我的审批」页看到 `STUB-n` → 点通过 → MySQL 查 `T_AUTH_ITSM_CALLBACK.APPROVE_RESULT` 更新、桩日志出现 `applications/{callbackId}/approve` 调用。
- 整分支 review（用 requesting-code-review 或等效流程），确认无 `origin` 推送后，只推 `mine master`。
