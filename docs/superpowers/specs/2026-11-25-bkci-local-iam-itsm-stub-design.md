# 本地 IAM/ITSM 协议兼容桩设计（2026-11-25）

## 意图与原因

本地 bk-ci 权限中心当前是空白页：`BK_CI_AUTH_PROVIDER=sample` 让 19 个 sample service 返回空列表 / `true` / `TODO`，不落库；`BK_CI_IAM_URL_PREFIX` 与 `BK_CI_ITSM_URL_PREFIX` 为空导致前端 `new URL()` 抛错、iframe 永久 loading。用户希望基于上游蓝鲸 IAM/ITSM 的开源实现与接口，做一个**简化的本地桩**，让本地 `auth.idProvider=rbac` 的真实链路原样跑通，权限中心页面能看到数据、能走通「列表 → 申请 → 审批 → 成员生效」。上游 IAM（Go，MIT）和 ITSM（Django，MIT）代码开源，但依赖 PaaS / APIGW / ESB / SSM / 统一登录，不适合整套拉起；bk-ci 侧已经把调用契约钉死，按契约做桩即可，不必照搬上游实现。

## 已确认的现状（勘察结论）

- `sample` provider：19 个空壳 service 返回空 / `true` / `TODO`，`devops_ci_auth` 中 `T_AUTH_RESOURCE_GROUP`、`T_AUTH_RESOURCE_GROUP_MEMBER`、`T_AUTH_RESOURCE_GROUP_APPLY`、`T_AUTH_ITSM_CALLBACK`、交接表均为 0 行；已有 19 个资源类型、104 个 action、66 个 group config（种子数据，但 sample 不消费）。
- IAM SDK 2.0.3（`iam-java-sdk-2.0.3.jar`）：所有 SDK 调用以 `auth.apigwUrl` 为基址，鉴权头仅 `x-bkapi-authorization={"bk_app_code":"bk_ci","bk_app_secret":"..."}`；响应必须是 SDK 信封 `{"code":0,"message":"OK","result":true,"data":...}`，`code` 必须是数值 0。
- ITSM 调用走 `BkHttpRequestService`，除信封外还要求 HTTP 2xx、`result=true`、`message="success"`（cancel）、`data.is_passed`（token verify）。
- 前端「我的申请」「我的审批」是**纯 iframe**：分别指向 `BK_IAM_URL_PREFIX/apply?system_id=bk_ci_rbac&source=externalApp` 与 `BK_ITSM_URL_PREFIX/#/ticket/approval-iframe`（组件会在前缀与 path 间补 `/`，前缀不要带尾斜杠或 `#`）。没有 postMessage 握手，只有 `onLoad` 清 spinner。
- **两条链路在代码里是独立的，不能混为一条**（builder review 确认）：`createRoleGroupApplicationV2` 走 IAM 侧用户组申请，成员由 `syncIamGroupMembersOfApply` 从 IAM members 接口同步；`RbacPermissionItsmCallbackService` / `AuthItsmCallbackListener` 的 ITSM 回调只处理项目分级管理员审批，按 `sn` 查 `T_AUTH_ITSM_CALLBACK` 后调 IAM `applications/{callbackId}/approve` 或 `cancel`。两条都要各自有可观察的落库结果。
- IAM 模型需 `support-files/bkiam-rbac/0003~0007*.json` 经 `do_migrate.py` 导入（调用 `/ping`、`/api/v1/model/systems/{id}/query` 等）。模型里 `system_id=bk_ci_rbac`；provider_config.host 指向 `ci-auth.service.consul:21936`。
- bk-ci 暴露的回调：ITSM `/ms/auth/api/external/auth/itsm/{create,update}_callback`；IAM 资源回调 `/ms/auth/api/open/auth/resource/{projects,instances/list}`（Basic `bk_iam:<token>`）。桩触发审批回调时需携带 `sn`/token 以通过校验。
- `deploy/local/bkenv.properties` 同一批 IAM/ITSM 变量被重复赋值，后面的空值覆盖前面的；配置必须改在文件尾部的覆盖块才生效。

## 目标 / 非目标 / 反目标

- **目标**：本地 `auth.idProvider=rbac` 能跑通真实 bk-ci 代码路径（IAM SDK + ITSM service + 回调 listener）；权限中心「我的申请 / 我的审批」iframe 都能看到数据；**两条独立链路都打通最小闭环**：① IAM 用户组申请链（申请加入组 → IAM approve → bk-ci 同步成员 → `T_AUTH_RESOURCE_GROUP_MEMBER` 出现行）；② ITSM 项目审批链（项目分级管理员申请 → 桩审批 → ITSM 回调 → IAM approve/cancel → 申请状态落库）；桩服务可作为后续集成测试 test double。
- **非目标**：不跑上游 IAM/ITSM 真身；不实现全量 IAM 管理 API（迁移/监控等非主链路接口按需再补）；不改 bk-ci 的 auth 主逻辑；桩服务运行时不写 `devops_ci_auth` 业务库（仅允许一次性 setup SQL 预置测试数据，见下）；不追求与生产蓝鲸环境一致的权限语义（只做够用的本地模拟）。
- **反目标（做了就算失败）**：把桩逻辑写进 `provider/sample` 造成分叉；直接改 bk-ci 业务代码适配桩；桩依赖 PaaS/APIGW/ESB/Redis 等外部底座；把凭据或运行态数据提交进仓库。

## 方案比较

1. **协议兼容桩服务（选用）**：在 `deploy/local` 下加一个独立 Kotlin + Spring Boot 服务，实现 bk-ci 实际调用的 IAM/ITSM 接口子集 + 两个 iframe 页面；bk-ci 保持 `rbac`，把 `auth.apigwUrl`、`itsm.url`、前端两个前缀指过去。优点是不 fork bk-ci 代码，桩可复用为测试替身；代价是接口面较宽、需要精确匹配信封与 DTO。
2. **改 sample provider 做有状态 mock**：注入现有 DAO、补种子数据、替换 iframe 页面。最快，但完全绕开真实协议、与上游 sample 分叉，升级要重做，且不能复用为协议级测试替身。
3. **裁剪部署上游真身**：Go 版 IAM + MySQL/Redis + Django ITSM，还要顶掉 APIGW/ESB/SSM。最贴近生产但依赖最重，与「本地别白屏」目标不匹配。

选择 1；语言用 Kotlin + Spring Boot（Java 17 / Gradle 8.10.2，与仓库后端同栈），不选 Python——尽管 `do_migrate.py` 是 Python，长期维护应与技术栈一致。

## 架构与数据流

```
浏览器 ──iframe /apply、#/ticket/approval-iframe──▶ 桩服务 (HTML 页)
  │                                                      │ 读写桩自己的库
bk-ci auth ──IAM SDK (x-bkapi-authorization)────────▶ 桩服务 (IAM API)
bk-ci auth ──BkHttpRequestService──────────────────▶ 桩服务 (ITSM API)
桩服务 ──HTTP 回调 create/update_callback──────────▶ bk-ci auth (gateway:80/ms/auth/...)
```

桩服务自带状态（H2 文件库或 SQLite，选 H2，见实现裁决），**不写** `devops_ci_auth`。种子数据来自 `support-files/bkiam-rbac/*.json` 的轻量解释（只取 system / resource_type / action / action_groups 供页面展示与列表校验），不需要导入 144 个 action 的完整权限树即可让页面有内容；需要精确匹配的 action id 时按 bk-ci 实际传入值透传。

## 接入集成、部署与交互流程

### 接入方式（不改 bk-ci 业务代码）

只做两件事：compose 加一个容器；改 `deploy/local/bkenv.properties` **尾部覆盖块**（同一批变量在文件前部被重复声明，尾部赋值才最终生效）。三个指针：

| 调用方 | 配置项 | 生效配置键 | 指向 |
|---|---|---|---|
| IAM SDK | `BK_CI_IAM_APIGW_URL` | `auth.apigwUrl` | `http://iam-stub:8080`（容器网内） |
| ITSM service | `BK_CI_ITSM_APIGW_URL` | `itsm.url` | `http://iam-stub:8080` |
| 浏览器 iframe | `BK_CI_IAM_URL_PREFIX` / `BK_CI_ITSM_URL_PREFIX` | 前端全局变量 | `http://localhost:8081/iam-stub` / `http://localhost:8081/itsm-stub` |

再加 `BK_CI_AUTH_PROVIDER=rbac` 激活 rbac beans。桩按 IAM SDK 信封（`code:0`）回包，SDK 无感知；无需改 bk-ci 任何 Kotlin 代码。

注意 `deploy/local/bkenv.properties` 被 `.gitignore` 忽略且含本地凭据，不能直接提交；可提交模板为 `deploy/local/iam-stub/bkenv-iam-stub.env`，部署时把其内容追加到该文件末尾。

### 部署位置

```
deploy/local/iam-stub/          ← 新增独立 Kotlin Gradle 子项目
  Dockerfile                    ← JDK17 运行 fat jar
  src/main/kotlin/...           ← IAM 控制器 + ITSM 控制器 + 两个 HTML 页面
  src/main/resources/application.yml  ← H2 文件库、端口、种子路径
  setup-local-auth.sql          ← 一次性预置 devops_ci_auth（用户已同意）
deploy/local/docker-compose.yml ← 新增服务 iam-stub，加入 bkci 网络
  内网 iam-stub:8080  → bk-ci auth 调用
  宿主 localhost:8081 → 浏览器 iframe 访问
  volume              → H2 文件持久化
```

不连 MySQL/Redis，不并入 `core:auth`，不引入 PaaS/APIGW/ESB/SSM。

### 展示位置

不新增菜单和路由，复用权限中心已有的两个 iframe 位置：

- 「我的申请」→ iframe `/apply` → IAM 用户组申请单（sn / 状态 / 申请人 / 组）+ 通过/驳回按钮；对应 `src/frontend/devops-permission/src/views/my-permission/my-apply.vue`。
- 「我的审批」→ iframe `#/ticket/approval-iframe` → ITSM 项目审批工单 + 通过/驳回按钮；对应 `src/frontend/devops-permission/src/views/my-permission/my-approval.vue`。
- 「申请权限」页是 bk-ci 原生页，已调用 `/ms/auth/api/user/auth/apply/*`，不用改。

页面由桩服务吐最简 HTML（内联 CSS），只为让 iframe 有数据且可操作，不复刻蓝鲸 UI。

### 交互流程

链一：用户组申请（IAM 侧）

```
[申请权限页] 选组提交
  → bk-ci POST /groups/-/applications/        → 桩建申请单，返回 {ids}
  → bk-ci 写 T_AUTH_RESOURCE_GROUP_APPLY
[我的申请 iframe] 列出单 → 点「通过」
  → 桩 POST /applications/{id}/approve/
  → 桩同时更新 belong=true 与 members 接口
[定时] bk-ci syncIamGroupMembersOfApply
  → /users/{u}/groups/belong/ 判定 belong
  → /groups/{id}/members/ 拉详情
  → 写 T_AUTH_RESOURCE_GROUP_MEMBER，单据置 SUCCEED
```

链二：项目审批（ITSM 侧）

```
[创建项目]
  → bk-ci POST grade_managers/-/applications/（带 callbackUrl）
  → 桩生成工单，返回 {id, sn}
  → bk-ci 写 T_AUTH_ITSM_CALLBACK(sn, callbackId, applyId)
[我的审批 iframe] 列出工单 → 点「通过」
  → 桩 POST bk-ci /ms/auth/api/external/auth/itsm/create_callback
  → bk-ci 调桩 /token/verify/ 验 token → 按 sn 查回调表
  → 调桩 POST /applications/{callbackId}/approve/ 拿 role_id
  → bk-ci 写项目资源、派发组创建事件
```

关键：真实环境里 ITSM 工单由 IAM 调 ITSM 创建，bk-ci 只传 `callbackUrl` / `title` / `content`。所以桩收到项目申请时必须自己生成工单记录，这是链二的起点。

## 桩服务接口清单（必须实现的最小集）

所有 IAM SDK 接口基址 = `auth.apigwUrl` + 下列路径，`{system}` 取自 `auth.iamSystem`（本地将设为 `bk_ci_rbac`）。响应统一 `{"code":0,"message":"OK","result":true,"data":...}`，`code` 为数值。

### IAM 基础与策略

- `GET /api/v1/model/systems/{system}/token` → `{"token":"stub-token"}`（TokenServiceImpl 要求 `data.token` 非空）。
- `GET /api/v1/model/systems/{system}/query` → `SystemFieldDTO` 形状（监控页用；可先返回最小对象）。
- `POST /api/v2/policy/systems/{system}/auth/` → `{"allowed": true}`（或按桩内策略判断）。
- `POST /api/v2/policy/systems/{system}/auth_by_actions/` → `{"<actionId>": true}`。
- `POST /api/v2/policy/systems/{system}/query/` → `{"op":"AND","content":[]}`（非空表达式 = allowed）。

### IAM V2 management（分级管理员 / 子集管理员 / 组 / 成员 / 申请）

- 分级管理员：`POST/GET/PUT/DELETE /api/v2/open/management/systems/{system}/grade_managers/[/{id}/]`；申请 `POST .../grade_managers/-/applications/`、`POST .../grade_managers/{id}/applications/`；`POST .../grade_managers/{id}/subset_managers/`。
- 子集管理员：`GET/POST .../subset_managers/{id}[/]`，`DELETE .../subset_managers/{id}/`。注意更新子集管理员是 **POST 无尾斜杠**（SDK 字节码确认），不是 PUT。
- 组列表：`GET .../grade_managers/{id}/groups/?page_size=&page=`、`GET .../subset_managers/{id}/groups/` → `{"count":n,"results":[V2ManagerRoleGroupInfo]}`（字段：`id,name,description,readonly,user_count,department_count,subject_template_count,joined,apply_disable`）。搜索参数按名解析，HashMap 顺序不保证。
- 组操作：`POST .../grade_managers/{id}/groups/`（返回 `[<int>]`）、`POST .../subset_managers/{id}/groups/`、`PUT/DELETE .../groups/{groupId}/`、`POST .../groups/{groupId}/policies/`、`GET .../groups/{groupId}/policies/`、`GET .../groups/{groupId}/policies/-/actions/`。
- 成员：`POST .../groups/{groupId}/members/`、`GET .../groups/{groupId}/members/`（`{"count","results":[RoleGroupMemberInfo]}`）、`DELETE .../groups/{groupId}/members/?type=&ids=`、`PUT .../groups/{groupId}/members/-/expired_at/`、`POST .../groups/-/renew/applications/`。
- 归属校验：`GET .../users/{userId}/groups/belong/?group_ids=`、`GET .../departments/{deptId}/groups/belong/?group_ids=`、`GET .../group_member_types/{type}/members/{memberId}/groups/-/details/?group_ids=`。其中 `verifyGroupValidMember`（users/belong → `{"<groupId>":{"belong":true,...}}`）是用户组申请链判定成员生效的入口，必须与 `/groups/{id}/members/` 的审批结果一致。
- 申请：`POST .../groups/-/applications/` → `{"ids":[...]}`；审批 `POST .../applications/{callbackId}/approve/` → `{"id","role_id"}`；取消 `PUT .../applications/{callbackId}/cancel/` → `message` 必须为 `"OK"`。
  - **精确响应形状（builder review 补齐）**：`ApplicationVO` 只有 `ids`；`GradeManagerApplicationResponse` = `{id:int, sn:string}`，id/sn 由桩生成并回写 `STUB_APPLICATION`，bk-ci 会把它们存进 `T_AUTH_ITSM_CALLBACK.APPLY_ID/SN`；`CallbackApplicationResponese`（SDK 原拼写）= `{id:int, role_id:int}`，`role_id` 取对应 grade manager 的 id，bk-ci 用它驱动组创建。`sn` 用 `STUB-<递增整数>`；`callbackId` 是 bk-ci 生成并随申请传入的 UUID 字符串（见 `PermissionGradeManagerService.kt` 的 `UUIDUtil.generate()`），桩必须原样落库并在 approve/cancel 时用它定位单据；响应 `id` 仍是桩的自增整数，`role_id` 取 grade manager id。bk-ci 按 sn 查回调行，两条信息都要保留。
- 模板：`GET .../grade_managers/{id}/subject_templates/`、`GET .../groups/{groupId}/subject_templates/`（可先返回 `{"count":0,"results":[]}`）。

### IAM 迁移接口（仅当启用迁移链路时；默认可返回 ok 壳）

基址 = `auth.webHost`（`/o/bk_iam`），带 `?token=`，要求真实 2xx + 信封：
`/api/v2/open/migration/bkci/task/`（POST/GET）、`/legacy_task/`（POST）、`/legacy_task/{id}/`（GET）、`/data/`（GET）。默认返回 `{"status":"SUCCESS"}` / `{"id":1}` / `{"count":0,"results":[]}` 即可。

### ITSM

基址 = `itsm.url`，要求 HTTP 2xx、信封 `code=0,result=true`：

- `POST /token/verify/` → `{"is_passed": true}`。
- `GET /get_ticket_status?sn=<sn>` → `{"current_status":"FINISHED"|"RUNNING"}`（bk-ci 把 `REVOKED`/`FINISHED` 视为终态）。
- `POST /operate_ticket/` → `message="success"`（bk-ci 的 cancel 调用检查）。
- 桩在项目审批「通过 / 驳回」时，主动 POST bk-ci 的 `/ms/auth/api/external/auth/itsm/create_callback` 或 `update_callback`，body 含 `title,current_status,sn,ticket_url,update_at,updated_by,approve_result("true"/"false"),token,last_approver`；`token` 需与 `/token/verify/` 一致以便通过 `RbacPermissionItsmCallbackService` 校验。
  - **回调地址（builder review 修正）**：优先使用 bk-ci 在 `GradeManagerApplicationCreateDTO.itsmCreateCallBackUrl` / 更新 DTO 中传入的地址；为空时用环境变量 `BKCI_CALLBACK_BASE_URL`，compose 内默认 `http://gateway:80`。**不能硬编码 `http://localhost:8080`**——从桩容器内访问不到宿主 localhost。本地渲染的 `itsm.callback.create.url` / `update.url` 也需改成 gateway 容器内可达地址，否则回调链断开。
  - ITSM 链观察点：callback → `T_AUTH_ITSM_CALLBACK` 按 sn 查行并更新审批结果 → IAM `applications/{callbackId}/approve` 或 `cancel`。成员落 `T_AUTH_RESOURCE_GROUP_MEMBER` 是 **IAM 用户组申请链**的观察点（经 `syncIamGroupMembersOfApply` 从桩的 `/groups/{id}/members/` 同步），不要与 ITSM 链混淆。

### 前端 iframe 页面

- `GET /apply?system_id=bk_ci_rbac&source=externalApp[&id=...]`：最小 HTML 页，列 **IAM 用户组申请单**（sn、状态、申请人、目标组），提供「通过 / 驳回」按钮，按钮调桩的 IAM `applications/{callbackId}/approve` 或 `cancel`；通过后同时更新桩的两个接口：`/users/{userId}/groups/belong/?group_ids=` 返回 `belong=true`（bk-ci `syncIamGroupMembersOfApply` 用它判断已加入），`/groups/{id}/members/` 返回成员详情（bk-ci `getAllRoleGroupMembersV2` 用它落 `T_AUTH_RESOURCE_GROUP_MEMBER`）。样式可用简单内联 CSS；不需要复刻蓝鲸 UI。
- `GET /#/ticket/approval-iframe?system_id=bk_ci_rbac&source=externalApp`（hash 路由）：最小 HTML 页，列 **ITSM 项目审批工单**（对应 `T_AUTH_ITSM_CALLBACK` 的 sn），按钮触发上述 ITSM 回调 + IAM approve/cancel。注意前缀应为不带 `#` 的绝对 URL（例如 `http://localhost:8081/itsm-stub/#/ticket/approval-iframe` 由组件拼出，因此配置前缀用 `http://localhost:8081/itsm-stub`）。
- 这两个页面是让本地 iframe「有数据且可操作」的关键；若只做 JSON API，iframe 仍白屏。

## 接线方式（本地部署）

- 新增 `deploy/local/iam-stub/`：`Dockerfile`（多阶段构建，JDK17 运行 Spring Boot fat jar）、`src/`（Kotlin 源码）、`settings.gradle.kts` + `build.gradle.kts`（**完全独立的 Gradle build**，不注册进主 `src/backend/ci/settings.gradle.kts`——该目录不在主 build 树内，且主 build 的 `allprojects` 会套用腾讯 boot 插件带来无关副作用；复用仓库 Gradle 8.10.2 wrapper，用 `gradlew -p` 调用）、`application.yml`（H2 文件库、端口、种子路径）。
- 新增 `deploy/local/docker-compose.yml` 服务 `iam-stub`：加入 `bkci` 网络，映射宿主端口（建议 IAM 8081 / ITSM 页面 8082，或单端口 8081 用不同路径区分），`environment` 注入 app code/secret、system id、回调地址（`BKCI_CALLBACK_BASE_URL=http://gateway:80`，容器内可达）。浏览器可达的 iframe 前缀必须发布到宿主。
- `deploy/local/bkenv.properties` 在尾部覆盖块设置：`BK_CI_AUTH_PROVIDER=rbac`、`BK_CI_IAM_APIGW_URL=http://iam-stub:8080`（容器间）、`BK_CI_ITSM_APIGW_URL=http://iam-stub:8080`、`BK_CI_IAM_SYSTEM_ID=bk_ci_rbac`、`BK_CI_IAM_MIGRATE_TOKEN=stub-token`、`BK_CI_IAM_URL_PREFIX=http://localhost:8081/iam-stub`、`BK_CI_ITSM_URL_PREFIX=http://localhost:8081/itsm-stub`。重新渲染并重启 auth / frontend 容器使配置生效。
- 迁移模型（可选）：保留 `support-files/bkiam-rbac/` JSON 作为种子来源；桩实现 `/ping` 与 `/api/v1/model/systems/{id}/query`，允许 `do_migrate.py` 跑通。不强制要求初始化 Job 跑迁移——桩自身读 JSON 文件生成列表即可。

## 数据模型（桩私有库）

最小表（H2）：`STUB_GROUP(id,name,description,project)`、`STUB_MEMBER(group_id,type,id,expired_at)`、`STUB_APPLICATION(id,sn,group_ids,applicant,status,callback_id,approve_result,external_callback_id)`、`STUB_GRADE_MANAGER(id,name,project)`、`STUB_TICKET(sn,status,token,callback_id,apply_id,external_callback_id,callback_url)`。`external_callback_id` 保存 bk-ci 的 UUID，`callback_url` 保存创建工单时传入的回调地址。种子：启动时读 `support-files/bkiam-rbac/0003~0007*.json`，至少插入若干示例 grade manager / group / member，使列表页非空；action/resource_type 列表从 0005/0003 解析供校验用。

## 本地测试前置（一次性 setup SQL）

用户已确认允许为本地测试预置 `devops_ci_auth`，但**桩服务运行时仍不写该库**，预置是一次性人工/脚本动作，不提交运行态数据。新增 `deploy/local/iam-stub/setup-local-auth.sql`：从本地已有的 `devops_ci_project.T_PROJECT` 读取项目英文代号（默认 `demotest`），插入对应的 `T_AUTH_RESOURCE_GROUP` 映射行，其中 IAM 组 ID 必须与桩种子 group id `10001` 一致，否则 `syncIamGroupMembersOfApply` 找不到对应行；脚本幂等，重复执行不产生重复行。

两条链的观察点各自明确：

- **IAM 用户组申请链**：用户在 bk-ci「申请权限」页提交 → `POST /groups/-/applications/` → bk-ci 写 `T_AUTH_RESOURCE_GROUP_APPLY` → 桩 `/apply` 页审批通过 → 桩 `/users/{userId}/groups/belong/` 返回 `belong=true` + `/groups/{id}/members/` 返回成员详情 → bk-ci 定时 `syncIamGroupMembersOfApply` 判定成功后 `syncIamGroupMember` → `T_AUTH_RESOURCE_GROUP_MEMBER` 出现行、单据状态置 `SUCCEED`。
- **ITSM 项目审批链**：桩 `#/ticket/approval-iframe` 页审批 → 回调 bk-ci → `T_AUTH_ITSM_CALLBACK` 按 sn 命中并更新 `APPROVE_RESULT` → IAM approve/cancel 被调用。

## 约束与验证

- 不提交任何凭据、运行日志、下载产物；本地示例 appSecret（`c28aee...`）来自现有 rendered 配置，视为本地开发值。
- 验证：先写契约测试（信封字段、`code` 为数值、`message` 取值、各路径动词、ITSM 回调 body）；`./gradlew test`（桩模块）；重启本地栈后分别手动走两条链——①「我的申请 → 加入用户组 → IAM 审批 → `T_AUTH_RESOURCE_GROUP_MEMBER` 出现行」，②「我的审批 → 项目审批 → ITSM 回调 → `T_AUTH_ITSM_CALLBACK.APPROVE_RESULT` 更新」；`git diff --check` 干净；整分支 review 后只推 `mine master`，绝不推 `origin`。
- 实现顺序建议：TDD 先写接口契约测试 → 桩最小骨架（信封 + token + 策略）→ management 列表/成员/申请 → ITSM 与回调 → iframe 页面 → compose 接线与端到端验证。

## 实现裁决（本次已定）

- 语言 / 框架：Kotlin + Spring Boot（Java 17，Spring Boot 3.4.0 系列，Gradle 8.10.2），**独立 Gradle build**，不并入 `core:auth`，也不注册进主 `settings.gradle.kts`。
- 状态存储：H2 文件库（随桩容器 volume 持久化），不连 `devops_ci_auth`，不引入 MySQL/Redis 外部依赖。
- 审批交互：桩提供最小 HTML 页直接操作，不对接真实 ITSM 前端流程；通过回调与 IAM approve 接口保持与 bk-ci 真实链路一致。
- 迁移接口：默认返回 ok 壳，不实现全量迁移数据面；如后续需要再补。
- **两条链都做最小闭环（用户确认）**：IAM 用户组申请链与 ITSM 项目审批链各有独立页面、独立落库观察点，不用一条链冒充另一条。
- **允许一次性 setup SQL 预置 `devops_ci_auth`（用户确认）**：仅作为本地测试前置，桩服务运行时绝不写该库；提交物只包含 setup SQL 脚本，不包含运行态数据。
- **回调地址（builder review 裁决）**：优先用 bk-ci 传入的 callbackUrl，为空则回退到 `BKCI_CALLBACK_BASE_URL=http://gateway:80`；禁止硬编码宿主 localhost。
- **申请响应字段（builder review 裁决）**：按 `ApplicationVO` / `GradeManagerApplicationResponse` / `CallbackApplicationResponese` 三组的精确字段实现，`sn=STUB-<n>`，callbackId 为 bk-ci 传入的 UUID 字符串并原样保存，`role_id` 取 grade manager id。

## 留给实现者的开放项（可在计划阶段细化）

- 单端口还是双端口暴露 IAM / ITSM 页面（影响 iframe 前缀配置，当前倾向单端口 8081 + 路径区分）。
- H2 文件路径与 compose volume 命名；种子数据的具体示例条数。
- fallback：若本地 `rbac` 模式启动因其它 SSO/ESB 依赖报错，记录并按需补最薄的 ESB/登录桩（不在本次范围，作为风险项）。
