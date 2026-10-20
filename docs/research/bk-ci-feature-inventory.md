# BK-CI 功能清单与 CI 承载能力评估（基于仓库一手来源）

- 调研日期：2026-10-20
- 调研对象：`/home/xsg/aicode/bk-ci`（master @ `367b10e4`，`git describe` = `v4.2.0-rc.8-209-g367b10e46fd`）
- 一手来源：源码（`src/backend`、`src/frontend`、`src/agent`）、仓库内文档（`docs/`、`README.md`）、`openspec/`、`CHANGELOG/`、`support-files/`、`helm-charts/`、`docker-images/`
- 口径说明：本文所有结论均给出仓库内文件路径；未在仓库内找到实现的能力一律标"缺失/未见"，不以外部印象补充。

---

## 一、结论先行

**能承担持续集成（CI）研发工作，核心 CI 能力完整度高；但它是"CI 平台"而非"全功能 GitLab/Jenkins"。**

1. **CI 主链路完整**：流水线模型（Stage/Job/Step 三层 + 变量/参数/模板/版本/草稿）、六类触发（Webhook/定时/手动/OpenAPI/远程/子流水线）、执行控制（并发互斥、重试、取消、超时、人工审核、失败处理策略、矩阵并行）、多形态构建资源（Docker/K8s/私有单机/私有集群/无编译环境）、代码源拉取、制品归档、构建日志与实时输出、权限、通知、度量报表——全部有实现且有对应 API 与前端页面。
2. **配套研发域基本齐全**：质量红线（含 CodeCC 指标门禁）、制品库、凭证、环境/构建机管理、度量、通知、RBAC 权限、OpenAPI（API 网关 486 个资源）、AI 助手，均有独立微服务。
3. **落地可运行**：Docker 镜像、Helm Chart（含全量微服务模板与初始化 Job）、单体 `boot-assembly.jar` 三种打包/部署形态齐备；CI 工作流（GitHub Actions）覆盖 backend/frontend/agent/sql。
4. **但有明确边界**：
   - **主流 CI 的"cache:（跨任务依赖缓存）"与"里程碑（milestone）"两类概念在仓库内无实现**；
   - **代码检查、编译加速、制品库存储、登录鉴权等依赖外部系统**（BK-CodeCC、BK-Turbo、BK-Repo、蓝鲸 IAM），独立部署不含这些（`docs/overview/installation.md`）；
   - **内置/默认插件数量少，插件生态在外部仓库**（`helm-charts/core/ci/base/values.yaml` 默认 9 个插件全部从 GitHub `TencentBlueKing/ci-*` 下载）；
   - **测试代码占比低**（约 4.5%），单体包 `boot-assembly` 未依赖 repository/metrics/ai 等 biz 实现。

**功能齐全度评价：CI 核心 = 完整；配套研发域 = 完整（但部分依赖外部系统）；CD/发布编排 = 部分；工程测试与文档 = 偏弱。**

---

## 二、功能清单表

### 2.1 流水线核心能力（`src/backend/ci/core/process/` + `core/common/common-pipeline`）

| 功能域 | 能力细节 | 证据（文件路径） | 完整/部分/缺失 |
|---|---|---|---|
| 流水线模型层级 | `Model → Stage → Container(Job) → Element(Task)` 四层；Job 分触发容器/普通容器/虚拟机构建容器/Job 模板容器 | `src/backend/ci/core/common/common-pipeline/src/main/kotlin/com/tencent/devops/common/pipeline/container/Stage.kt`、`…/container/Container.kt`、`…/container/VMBuildContainer.kt`、`…/container/TriggerContainer.kt`、`…/container/JobTemplateContainer.kt` | 完整 |
| 任务（Step）类型 | 内置元素多态注册：Git/GitLab/GitHub/SVN 拉码、Linux/Windows 脚本、手动触发、远程触发、定时触发、人工审核、子流水线调用、质量门禁进出、市场插件（有编译/无编译）、Step 模板、矩阵状态 | `src/backend/ci/core/common/common-pipeline/src/main/kotlin/com/tencent/devops/common/pipeline/pojo/element/Element.kt`（`@JsonSubTypes` 注册表）、`…/pojo/element/StepTemplateElement.kt` | 完整（内置种类有限，大量能力经市场插件扩展） |
| 变量/参数 | 构建参数（含参数分组）、公共变量、公共变量组（含历史/引用关系）、变量引用解析与校验、表达式 | `…/common/pipeline/pojo/BuildParameterGroup.kt`、`…/pojo/PublicVarGroupVariable.kt`、`…/pojo/PublicVarGroupRef.kt`、`…/utils/ModelVarRefUtils.kt`、`…/utils/ModelVarRefValidator.kt`、`src/backend/ci/core/process/api-process/…/ServicePublicVarGroupResource.kt`、`src/backend/ci/core/process/biz-base/…/service/var/PublicVarGroupService.kt` | 完整 |
| 模板 | 流水线模板（V1/V2）、模板实例化、跨项目模板分发、模板版本、Job 模板、Step 模板 | `src/backend/ci/core/process/api-process/…/PipelineTemplateResource.kt`、`…/UserPipelineTemplateV2Resource.kt`、`…/UserTemplateInstanceResource.kt`、`…/BuildTemplateAcrossResource.kt`、`…/common/pipeline/container/JobTemplateContainer.kt` | 完整 |
| 版本管理 | 草稿/分支版本/正式版本/发布草稿/删除版本等动作；版本对比与历史 | `…/common/pipeline/enums/PipelineVersionAction.kt`、`src/backend/ci/core/process/api-process/…/UserPipelineVersionResource.kt`、`…/OpPipelineVersionResource.kt`、`…/common/pipeline/pojo/CreatePipelineAndSaveDraftRequest.kt` | 完整 |
| 手动/API 触发 | 手动启动（含参数预览）、OpenAPI 触发 | `src/backend/ci/core/process/api-process/…/user/UserBuildResource.kt`（`manualStartupInfo`/`manualStartup`）、`src/backend/ci/core/openapi/api-openapi/…/ApigwBuildResourceV3.kt`、`…/ApigwBuildResourceV4.kt` | 完整 |
| 定时触发 | Cron 多表达式、Quartz 调度、按代码库变更拦截（避免空跑）、高级表达式转换 | `src/backend/ci/core/process/biz-process/…/plugin/trigger/timer/quartz/PipelineQuartzService.kt`、`…/plugin/trigger/service/PipelineTimerTriggerTaskService.kt`、`…/plugin/trigger/service/PipelineTimerService.kt`、`src/backend/ci/core/process/biz-base/…/engine/interceptor/TimerTriggerScmChangeInterceptor.kt`、`…/common/pipeline/pojo/element/trigger/TimerTriggerElement.kt` | 完整 |
| 代码库 Webhook 触发 | 事件处理器：GitHub(push/PR/issue/comment/review/create)、TGit(push/MR/tag/note/review/issue)、SVN(commit)、P4(change/shelve)、GitLab 解析器、通用 SCM Git；触发匹配、参数下发、指标、锁 | `src/backend/ci/core/common/common-webhook/biz-common-webhook/…/handler/`（`GithubPrTriggerHandler.kt`、`TGitMrTriggerHandler.kt`、`SvnCommitTriggerHandler.kt`、`P4ChangeTriggerHandler.kt` 等）、`src/backend/ci/core/process/biz-process/…/webhook/parser/GitlabWebhookEventParser.kt`、`…/trigger/scm/ScmWebhookTriggerBuildService.kt`、`…/trigger/scm/WebhookTriggerMatcher.kt` | 完整 |
| 远程触发 | Remote 触发元素 + 触发类型枚举 | `…/common/pipeline/pojo/element/trigger/RemoteTriggerElement.kt`、`src/backend/ci/core/process/api-process/…/pojo/trigger/PipelineTriggerType.kt` | 完整 |
| Pipeline-as-Code（YAML） | YAML v2/v3 解析与互转、`on:` 触发（push/mr/tag/review/note/issue/schedule/manual/remote/tapd/delete）、concurrency、gate、matrix、通知、模板、仓库内 YAML 同步（PAC） | `src/backend/ci/core/common/common-pipeline-yaml/…/yaml/v3/models/on/`（`PushRule.kt`、`MrRule.kt`、`SchedulesRule.kt`、`RemoteRule.kt`、`TapdRule.kt`…）、`…/v3/models/Concurrency.kt`、`…/v3/models/gate/`、`…/v3/models/job/Job.kt`、`…/v3/models/step/Step.kt`、`src/backend/ci/core/process/biz-process/…/trigger/scm/PacWebhookEventListener.kt`、`…/yaml/PipelineYamlFileManager.kt` | 完整（除无 `cache:` 一级能力） |
| 并发控制 | 流水线级：Lock 类型、最大排队时长/数量、并发 group、同 group 取消旧构建、并发构建数量限制；Job 级：单节点/全节点并发数、互斥组、Agent 复用互斥；同阶段 Job 调度队列 | `…/common/pipeline/pojo/setting/PipelineSetting.kt`（lock/queue/group/并发构建数量限制字段）、`…/common/pipeline/option/JobControlOption.kt`（`singleNodeConcurrency`/`allNodeConcurrency`）、`…/common/pipeline/container/MutexGroup.kt`、`…/common/pipeline/container/AgentReuseMutex.kt`、`src/backend/ci/core/process/biz-engine/…/engine/control/MutexControl.kt`、`…/engine/control/DispatchQueueControl.kt` | 完整 |
| 重试/取消 | 插件级自动重试（次数）+ 手动重试、失败后手动跳过、整体重试（可清引擎变量表）、手动停止 | `…/common/pipeline/pojo/element/ElementAdditionalOptions.kt`（`retryWhenFailed`/`retryCount`/`manualRetry`/`manualSkip`）、`src/backend/ci/core/process/api-process/…/user/UserBuildResource.kt`（`retry`、`manualShutdown`）、`src/backend/ci/core/process/biz-engine/…/engine/control/BuildCancelControl.kt`、`…/common/pipeline/pojo/setting/PipelineSetting.kt`（`retryCleanEngineVariable`） | 完整 |
| 人工审核 / 门禁 | Stage 级人工审核（审核人、超时、审核变量、审核说明）、插件级人工审核、质量红线审核人/驳回、GitHub/TGit MR 审核联动 | `…/common/pipeline/option/StageControlOption.kt`（`manualTrigger`/`triggerUsers`/`timeout`/`reviewParams`）、`…/common/pipeline/pojo/StageReviewGroup.kt`、`…/common/pipeline/pojo/element/agent/ManualReviewUserTaskElement.kt`、`src/backend/ci/core/process/biz-engine/…/atom/task/ManualReviewTaskAtom.kt`、`src/backend/ci/core/quality/biz-quality/…/dao/v2/QualityRuleReviewerDao.kt` | 完整 |
| 插件失败处理策略 | 元素级：失败继续（自动/手动）、超时、运行条件（11 种 RunCondition）、前置暂停；插件元数据级：失败策略（自动继续/手动继续）、重试策略（自动/手动） | `…/common/pipeline/pojo/element/ElementAdditionalOptions.kt`（`RunCondition` 枚举）、`…/common/pipeline/option/StageControlOption.kt`、`…/common/pipeline/enums/JobRunCondition.kt`、`src/backend/ci/core/store/api-store/…/atom/enums/AtomFailPolicyEnum.kt`、`…/atom/enums/AtomRetryPolicyEnum.kt` | 完整 |
| Job/Stage 运行条件 | 上游 Stage 成功/失败/取消、自定义变量、自定义表达式、依赖 Job（dependOn） | `…/common/pipeline/enums/JobRunCondition.kt`、`…/common/pipeline/enums/StageRunCondition.kt`、`…/common/pipeline/option/JobControlOption.kt`（`dependOnType`/`dependOnId`）、`src/backend/ci/core/process/biz-engine/…/engine/control/DependOnControl.kt` | 完整 |
| 矩阵并行（matrix） | 策略/include/exclude、最大 256 例、最大并发、fastKill、自定义调度 | `…/common/pipeline/option/MatrixControlOption.kt`（`MATRIX_CASE_MAX_COUNT = 256`）、`…/common/pipeline/matrix/`、`…/utils/MatrixContextUtils.kt` | 完整 |
| 子流水线 | 子流水线调用元素、跨项目分发、引用查询 | `…/common/pipeline/pojo/element/SubPipelineCallElement.kt`、`src/backend/ci/core/process/api-process/…/BuildSubPipelineResource.kt`、`…/ServiceSubPipelineResource.kt`、`…/OpSubPipelineRefResource.kt` | 完整 |
| 超时/心跳/监控 | Job 准备与执行超时、任务超时、Agent 心跳与掉线处理 | `…/common/pipeline/option/JobControlOption.kt`（`prepareTimeout`/`timeout`）、`src/backend/ci/core/process/biz-engine/…/engine/control/BuildMonitorControl.kt`、`…/engine/control/HeartbeatControl.kt`、`…/common/pipeline/pojo/JobHeartbeatRequest.kt` | 完整 |
| 里程碑（milestone） | 仓库内无流水线 milestone 概念实现（`milestone` 仅命中 GitHub/TGit 代码平台数据模型） | `src/backend/ci/core/repository/api-repository/…/sdk/github/pojo/GithubMilestone.kt`、`src/backend/ci/core/repository/api-repository/…/pojo/git/GitMrInfo.kt`（均为外部平台字段） | 缺失 |
| 跨任务依赖缓存（`cache:`） | YAML 模型中无 `cache` 一级节点；未见构建工作区/依赖缓存的流水线级抽象 | `src/backend/ci/core/common/common-pipeline-yaml/src/main/kotlin/com/tencent/devops/process/yaml/v3/models/`（目录内无 Cache 模型） | 缺失 |

### 2.2 构建执行（`core/dispatch`、`core/worker`、`core/dockerhost`、`src/agent`）

| 功能域 | 能力细节 | 证据（文件路径） | 完整/部分/缺失 |
|---|---|---|---|
| 构建资源类型 | 公共 Docker、Kubernetes、私有单构建机、私有构建集群、MacOS/Windows DevCloud、无编译环境（AGENT_LESS）、工蜂 CI/Stream/BCS/PCG 等渠道 | `src/backend/ci/core/common/common-pipeline/src/main/kotlin/com/tencent/devops/common/pipeline/type/BuildType.kt`、`…/type/DispatchType.kt`、`…/type/agent/ThirdPartyAgentIDDispatchType.kt`、`…/type/agent/ThirdPartyAgentEnvDispatchType.kt`、`…/type/kubernetes/KubernetesDispatchType.kt`、`…/type/docker/DockerDispatchType.kt` | 完整 |
| Docker 构建机 | DockerHost 调度、镜像路由、构建调试、镜像资源白名单、无编译环境构建 | `src/backend/ci/core/dispatch/biz-dispatch-docker/…/dispatch/docker/service/DockerHostBuildService.kt`、`…/service/DockerRoutingService.kt`、`…/service/DockerResourceWhitelistService.kt`、`…/dispatch/docker/client/BuildLessStartHandler.kt`、`src/backend/ci/core/dockerhost/biz-dockerhost/…/dockerhost/services/DockerHostBuildService.kt` | 完整 |
| Kubernetes 构建 | K8s Job/Deployment/Ingress/镜像仓库、BCS（蓝鲸容器服务）双实现、K8s 无编译环境 | `src/backend/ci/core/dispatch/biz-dispatch-kubernetes/…/dispatch/kubernetes/service/KubernetesJobService.kt`、`…/service/KubernetesBuildLessService.kt`、`…/dispatch/kubernetes/bcs/service/BcsJobService.kt`、`src/backend/ci/core/dispatch/common-dispatch-kubernetes/` | 完整 |
| 私有构建机 | 私有单机/集群注册、构建任务分发、Docker 运行（含 CPU/内存上限）、互斥、预构建节点选择、监控 | `src/backend/ci/core/dispatch/biz-dispatch/…/dispatch/service/ThirdPartyAgentBuildService.kt`、`…/service/ThirdPartyAgentDockerService.kt`、`…/service/ThirdPartyAgentMonitorService.kt`、`…/dispatch/pojo/ThirdPartyAgentPreBuildAgents.kt`、`CHANGELOG/zh_CN/CHANGELOG-4.2.md`（"第三方构建机使用 Docker 运行构建任务时支持指定 CPU/内存上限"） | 完整 |
| 构建资源排队/配额 | 队列控制（Redis 排序队列、超上限不出队）、系统/项目级并发配额、配额统计调度 | `src/backend/ci/core/process/biz-engine/…/engine/control/DispatchQueueControl.kt`、`src/backend/ci/core/dispatch/biz-dispatch/…/dispatch/service/jobquota/JobQuotaBusinessService.kt`、`…/service/jobquota/JobQuotaManagerService.kt`、`src/backend/ci/core/dispatch/biz-dispatch/src/main/kotlin/com/tencent/devops/dispatch/cron/JobStatisticsScheduler.kt`、`src/backend/ci/core/dispatch/api-dispatch/…/pojo/enums/JobQuotaVmType.kt` | 完整 |
| Agent（Go） | devopsDaemon/devopsAgent/upgrader 三进程、跨 Linux/macOS/Windows、进程守护、证书、自动升级、安装脚本 | `src/agent/agent/README.md`、`src/agent/agent/Makefile`、`src/agent/agent/doc/guide/`（`installation.md`、`platform-windows.md`、`docker-builds.md`…）、`src/agent/agent-slim/` | 完整 |
| Worker（Kotlin） | 收发任务、脚本执行（shell/powershell/bat）、市场插件执行、日志上报、心跳 | `src/backend/ci/core/worker/worker-agent/`、`…/worker-common/src/main/kotlin/com/tencent/devops/worker/common/task/script/`、`…/worker-common/…/plugin/worker/task/market/MarketAtomTask.kt`（经 `MarketBuildAtomElement` 引用）、`…/worker-common/…/heartbeat/` | 完整 |
| 构建日志 | ES 存储、WebSocket 实时推送、日志打印接口 | `src/backend/ci/core/log/`（`api-log`/`biz-log`/`biz-log-sample`）、`src/backend/ci/core/websocket/`、`src/backend/ci/core/common/common-es/` | 完整 |
| 构建历史/归档 | 构建历史查询、多次执行记录、历史归档服务 | `src/backend/ci/core/process/api-process/…/user/UserBuildResource.kt`、`src/backend/ci/core/process/api-process/…/ServiceArchivePipelineResource.kt`、`support-files/sql/1001_ci_archive_process_ddl_mysql.sql`（归档库 `devops_ci_archive_process`） | 完整 |

### 2.3 插件体系（`core/store`、插件 SDK、研发商店）

| 功能域 | 能力细节 | 证据（文件路径） | 完整/部分/缺失 |
|---|---|---|---|
| 插件分类 | 类别：触发器类（TRIGGER）/任务类（TASK）；来源：自研/第三方；支持有编译/无编译运行 | `src/backend/ci/core/store/api-store/…/atom/enums/AtomCategoryEnum.kt`、`…/atom/enums/AtomTypeEnum.kt`、`…/common/pipeline/pojo/element/market/MarketBuildLessAtomElement.kt` | 部分（二级"分类（BUILD/DEPLOY…）"以 `T_CLASSIFY` 数据表维护，代码中仅 2 个顶层类别） |
| 上架流程 | 状态机：初始化→提交→构建→代码检查→测试→审核→发布/驳回/上架中止/下架，覆盖 CodeCC 检查、审核、版本 | `src/backend/ci/core/store/api-store/…/atom/enums/AtomStatusEnum.kt`（14 态）、`…/atom/enums/ApproveStatusEnum.kt`、`…/atom/enums/VersionTypeEnum.kt`、`src/backend/ci/core/store/biz-store/…/store/atom/service/impl/` | 完整 |
| 插件表单/配置规范 | 输入表单 Schema（组件类型、依赖表达式、校验规则）、错误码、国际化 | `…/common/pipeline/pojo/atom/form/enums/AtomFormComponentType.kt`、`src/backend/ci/core/store/api-store/…/atom/enums/FieldTypeEnum.kt`、`…/atom/enums/ErrorCodeTypeEnum.kt` | 完整 |
| 内置/默认插件 | 默认插件 9 个：checkout、run、SubPipelineExec、uploadArtifact、uploadReport、AcrossProjectDistribution、downloadArtifact、PerforceSync、CodeCCCheckAtom（全部从 GitHub `TencentBlueKing/ci-*` 下载）；触发器类插件随 DML 内置（TGit/P4/ScmGit/TAPD/Git/GitHub/SVN/GitLab 触发） | `helm-charts/core/ci/base/values.yaml`（`init.plugin.atoms`）、`support-files/sql/5001_init_dml/5001_ci_store-init_dml_mysql.sql`（`T_ATOM` 记录） | 部分（默认集合小，丰富插件在外部 `ci-plugins` 生态：`docs/wiki/pipeline_plugin_guidelines.md`） |
| 插件开发指引 | Java/Python/Golang/Nodejs 四语言开发文档、配置/输出规范 | `docs/wiki/pipeline_plugin_guidelines.md`、`docs/wiki/store_development_guidelines.md`、`docs/wiki/collaborative_development_guidelines.md` | 部分（正文外链到 `ci-plugins/ci-plugins-wiki`，仓库内无 SDK 源码） |
| 插件部署/初始化 | Helm 初始化 Job 通过 Store OpenAPI 部署默认插件并设为默认 | `helm-charts/core/ci/templates/init/init.plugin.yaml` | 完整 |
| 质量门禁插件 | 质量门禁进出元素 + 质量元数据 | `…/common/pipeline/pojo/element/quality/QualityGateInElement.kt`、`…/quality/QualityGateOutElement.kt` | 完整 |

### 2.4 代码库集成（`core/repository`）

| 功能域 | 能力细节 | 证据（文件路径） | 完整/部分/缺失 |
|---|---|---|---|
| 支持代码源 | SVN、Git、GitLab、GitHub、TGit、P4、通用 SCM（SCM_GIT/SCM_SVN/SCM_P4） | `src/backend/ci/core/common/common-api/…/enums/ScmType.kt`、`src/backend/ci/core/repository/biz-repository/…/service/loader/CodeRepositoryServiceRegistrar.kt`（`getServiceByScmType` 分支） | 完整（含 Coding 系需经 GitLab/Git 兼容接入，仓库内无独立 Coding 枚举） |
| 拉代码能力 | Git/GitHub/GitLab/SVN 拉码任务、浅克隆/全新检出/回退、SSH Agent、子模块等 | `src/backend/ci/core/worker/worker-common/…/plugin/worker/task/scm/CodePullTask.kt`、`…/task/scm/CodeGitPullTask.kt`、`…/task/scm/GithubPullTask.kt`、`…/task/scm/CodeSvnPullTask.kt`、`…/task/scm/util/SSHAgentUtils.kt` | 完整（P4 拉码以外部插件 `PerforceSync` 提供，见 `values.yaml`） |
| 代码库管理 | 仓库授权（OAuth/Token）、凭证绑定、文件浏览、MR 信息、PAC 项目同步 | `src/backend/ci/core/repository/api-repository/…/pojo/enums/RepoAuthType.kt`、`…/pojo/enums/TokenTypeEnum.kt`、`src/backend/ci/core/repository/biz-repository/…/service/RepoFileService.kt`、`…/service/RepositoryPacService.kt` | 完整 |
| 提交状态回写 | GitHub Check Run（含质量门禁报告写回 MR 评论）、MR 锁定提交 | `src/backend/ci/core/process/biz-process/…/trigger/check/PipelineBuildCheckRunResolver.kt`、`…/trigger/check/PipelineBuildCheckRunQualityService.kt`、`support-files/sql/5001_init_dml/5001_ci_store-init_dml_mysql.sql`（触发器的 `enableQualityReport`/`block` 配置） | 完整 |

### 2.5 配套研发能力

| 功能域 | 能力细节 | 证据（文件路径） | 完整/部分/缺失 |
|---|---|---|---|
| 代码检查 CodeCC | CodeCC OpenAPI 客户端（度量、工具分析、缺陷）、CodeCC 检查插件、CodeCC 任务/规则集权限、质量指标以 CodeCC 数据为源 | `src/backend/ci/core/common/common-codecc/…/plugin/codecc/CodeccApi.kt`、`…/plugin/codecc/pojo/CodeccMeasureInfo.kt`、`src/backend/ci/core/common/common-auth/common-auth-api/…/AuthResourceType.kt`（`CODECC_TASK`/`CODECC_RULE_SET`/`SCC_TASK`）、`support-files/i18n/quality/indicator_zh_CN.json`（`elementType: CodeCCCheckAtom`）、`support-files/sql/5001_init_dml/5001_ci_store-init_dml_mysql.sql`（`CodeCCCheckAtom`） | 部分（检查引擎在外部 BK-CodeCC，本仓库仅集成；`docs/overview/installation.md`：独立部署不含 CodeCC） |
| 质量红线 | 控制点/指标/元数据/规则/模板/拦截历史/审核人/每日报表，流水线内门禁进出 | `src/backend/ci/core/quality/biz-quality/…/dao/v2/`（`QualityControlPointDao`、`QualityIndicatorDao`、`QualityRuleDao`、`QualityRuleReviewerDao`）、`…/resources/v2/UserQualityRuleResourceImpl.kt`、`…/cron/QualityDailyReportJob.kt`、`src/backend/ci/core/process/biz-base/…/engine/service/PipelineBuildQualityService.kt`、`support-files/i18n/quality/` | 完整 |
| 制品库 | 流水线产物归档/下载、自定义目录、镜像、报告、跨项目分发，底层对接 BK-Repo（通用/Maven/Npm/Docker 等由 Repo 提供） | `src/backend/ci/core/artifactory/api-artifactory/…/enums/ArtifactoryType.kt`、`src/backend/ci/core/common/common-archive/…/archive/client/BkRepoClient.kt`、`…/archive/element/BuildArchiveGetElement.kt`、`helm-charts/core/ci/templates/init/init.bkrepo.yaml`、`README.md`（制品库能力描述） | 部分（存储/包管理由外部 BK-Repo 承担） |
| 凭证 | 11 种凭证类型（密码/Token/OAuth/密钥对/COS 等）、证书 | `src/backend/ci/core/ticket/api-ticket/…/pojo/enums/CredentialType.kt`、`…/pojo/enums/CertType.kt` | 完整 |
| 环境/构建机管理 | 环境、环境节点、第三方构建机注册与安装会话、升级、共享、Agent 引用关系 | `src/backend/ci/core/environment/api-environment/…/api/thirdpartyagent/BuildThirdPartyAgentResource.kt`、`…/pojo/thirdpartyagent/AgentInstallSession.kt`、`…/pojo/thirdpartyagent/AgentPipelineRef.kt`、`…/pojo/enums/AgentType.kt` | 完整 |
| 度量报表 | 流水线总览、插件执行/失败统计与趋势、错误码统计、构建资源（dispatch job）指标、CodeCC 数据接收 | `src/backend/ci/core/metrics/biz-metrics/…/resources/UserPipelineOverviewResourceImpl.kt`、`…/service/AtomStatisticsManageService.kt`、`…/service/AtomFailInfoManageService.kt`、`…/listener/DispatchJobMetricsListener.kt`、`src/frontend/devops-metrics/` | 完整 |
| 通知 | 邮件/RTX/微信/企业微信（单聊与群）/短信/语音，模板化消息 | `src/backend/ci/core/common/common-notify/…/notify/enums/NotifyType.kt`、`src/backend/ci/core/notify/biz-notify/…/notify/resources/ServiceNotifyMessageTemplateResourceImpl.kt`、`…/notify/resources/BuildNotifyResourceImpl.kt` | 完整 |
| 权限 | RBAC 权限中心接入：项目/流水线/模板/变量组/凭证/环境/制品目录/质量规则/CodeCC/编译加速等资源类型；IAM 资源、动作、分组初始化数据 | `src/backend/ci/core/common/common-auth/common-auth-api/…/AuthResourceType.kt`、`support-files/bkiam-rbac/0003_resource_20221223_iam-rbac.json`、`0005_action_20221213_iam-rbac.json`、`0006_group_20221213_iam-rbac.json` | 完整（依赖外部蓝鲸 IAM） |
| OpenAPI | API 网关资源 486 个，覆盖 Build/Auth/Atom/Artifactory/CallBack/Template/Quality/Repository 等 V3/V4 接口，JWT/AccessToken 过滤器 | `support-files/apigw/bk_apigw_resources_devops.yaml`（486 条 `resource:`）、`src/backend/ci/core/openapi/api-openapi/…/ApigwBuildResourceV4.kt` 等、`…/biz-openapi/…/AccessTokenFilter.kt` | 完整 |
| AI 能力 | 智能助手（流水线级会话）、LLM 配置、MCP Server、技能/提示词管理、构建失败分类器、构建 Agent 工具 | `src/backend/ci/core/ai/biz-ai/…/ai/service/AiChatService.kt`、`…/ai/service/AiMcpServerService.kt`、`src/backend/ci/core/ai/api-ai/…/UserAiSessionResource.kt`、`docs/ai/ai-memory-tuning-guide.md`、`support-files/sql/5001_init_dml/5001_ci_ai-init_dml_mysql.sql` | 完整 |
| 审计/回调 | 构建回调、审计日志、流水线回调监听 | `src/backend/ci/core/process/api-process/…/UserCallBackResource.kt`、`src/backend/ci/core/process/biz-process/…/audit/service/`、`src/backend/ci/core/common/common-audit/` | 完整 |

### 2.6 前端可用性（`src/frontend`）

| 功能域 | 能力细节 | 证据（文件路径） | 完整/部分/缺失 |
|---|---|---|---|
| 可视化编排 | 拖拽式 Stage/Job/插件编排、小地图、属性面板、矩阵组、插入阶段菜单 | `src/frontend/devops-pipeline/package.json`（`vuedraggable`）、`src/frontend/devops-pipeline/src/components/`（`MiniMap`、`ContainerPropertyPanel`、`AtomPropertyPanel`、`AtomSelector`）、`src/frontend/bk-pipeline/src/`（`Stage.vue`、`Job.vue`、`Atom.vue`、`MatrixGroup.vue`、`InsertStageMenu.vue`） | 完整 |
| YAML 编辑 | YAML 流水线编辑器、Diff 对比、可视化/YAML 双模式切换 | `src/frontend/devops-pipeline/src/views/subpages/YamlPipelineEditor.vue`、`src/frontend/devops-pipeline/src/components/YamlEditor.vue`、`…/components/YamlDiff.vue`、`…/components/ModeSwitch.vue` | 完整 |
| 执行与历史 | 执行详情、构建历史表、草稿调试、参数设置、版本历史 | `src/frontend/devops-pipeline/src/views/subpages/ExecDetail.vue`（同目录 `History.vue`、`edit.vue`、`preview.vue`）、`…/components/BuildHistoryTable/`、`…/components/PipelineDetailTabs/VersionHistorySideSlider.vue` | 完整 |
| 配套页面 | 插件商店、代码库、凭证、环境、质量、度量、权限、管理、创作流、编译加速 | `src/frontend/` 目录：`devops-atomstore/`、`devops-codelib/`、`devops-repo/`、`devops-ticket/`、`devops-environment/`、`devops-quality/`、`devops-metrics/`、`devops-permission/`、`devops-manage/`、`devops-flow/`、`devops-turbo/`、`devops-stream/` | 完整 |
| 技术栈 | Vue2.7（多数页面）+ Vue3（`devops-flow`、`devops-metrics`）并存，微前端（`public-path.js`、`nx.json`） | `src/frontend/devops-pipeline/package.json`、`src/frontend/devops-flow/package.json`、`src/frontend/devops-metrics/package.json`、`src/frontend/nx.json` | 部分（双栈并存，维护成本高） |

### 2.7 部署与运行

| 功能域 | 能力细节 | 证据（文件路径） | 完整/部分/缺失 |
|---|---|---|---|
| Docker 镜像 | 网关/后端/前端三类镜像构建脚本 + Dockerfile | `docker-images/core/ci/1.build_gateway_image.sh`、`2.build_backend_bkci_image.sh`、`3.build_frontend_image.sh`、`docker-images/core/ci/dockerfile/backend.bkci.Dockerfile`、`docker-images/core/ci/README.md` | 完整 |
| Helm Chart | 全量微服务模板（ai/artifactory/auth/dispatch/environment/log/metrics/misc/notify/openapi/process/project/quality/repository/store/ticket/turbo/websocket + gateway/frontend）、SQL/IAM/插件/BK-Repo/默认镜像初始化 Job、HPA、多集群 | `helm-charts/core/ci/templates/`、`helm-charts/core/ci/templates/init/`（`init.sql.yaml`、`init.iam-rbac.yaml`、`init.plugin.yaml`、`init.bkrepo.yaml`、`init.defaultImages.yaml`）、`helm-charts/core/ci/base/values.yaml` | 完整 |
| 单体打包 | `boot-assembly.jar` 整合多微服务；依赖清单含 artifactory/dispatch/environment/log/misc/notify/openapi/process/project/quality/ticket/websocket/store | `src/backend/ci/boot-assembly/build.gradle.kts`、`src/backend/ci/boot-assembly/src/main/kotlin/com/tencent/devops/AssemblyApplication.kt`、`docs/overview/source_compile.md`（"整合10个微服务"） | 部分（依赖清单**不含** `core:repository:biz-repository`、`core:metrics`、`core:ai`、`core:auth:biz-auth` 的实现，与 Helm 全量部署存在差距） |
| 微服务独立打包 | 21 个 `boot-*` 模块（含 boot-repository/boot-metrics/boot-ai/boot-auth/boot-dockerhost/boot-buildless 等） | `src/backend/ci/settings.gradle.kts`、`src/backend/ci/core/*/boot-*` | 完整 |
| 网关 | OpenResty/Nginx + Lua，Consul 服务发现、鉴权 | `src/gateway/`、`docs/overview/code_framework.md`（网关章节） | 完整 |
| CI 工作流 | backend/frontend/agent/sql/release/maven 发布 7 条流水线 | `.github/workflows/`（`backend.yml`、`frontend.yml`、`agent.yml`、`sql.yml`、`release.yml`、`publishMavenJar4CI.yml`） | 完整 |
| 安装文档 | K8s（推荐）与 Linux 两种部署路径、依赖组件说明 | `docs/overview/installation.md`、`docs/install/kubernetes.md`、`docs/install/linux.md` | 部分（Linux 文档仍写 RabbitMQ/CentOS7/JDK8，与当前技术栈存在版本滞后，见 `docs/install/linux.md` 基础环境章节） |

---

## 三、与主流 CI（GitLab CI / Jenkins）的差距

### 3.1 明显缺失

| 能力 | GitLab CI / Jenkins 对应 | 本仓库证据 |
|---|---|---|
| 跨任务依赖缓存 `cache:` | GitLab CI `cache:`、Jenkins stash/缓存插件 | `common-pipeline-yaml/…/v3/models/` 无 Cache 模型；全仓未见构建缓存的一级抽象（grep `cache` 仅命中 `TransferCacheService`、`QualityCacheService` 等无关实现） |
| 里程碑（milestone）门禁 | GitLab CI milestone 相关流水线约束 | 全仓 `milestone` 仅出现在 GitHub/TGit 数据模型：`core/repository/api-repository/…/sdk/github/pojo/GithubMilestone.kt` |
| 在仓库内的插件 SDK/示例 | Jenkins 自带大量内置步骤 | 插件 SDK 与规范外链至 `ci-plugins/ci-plugins-wiki`（`docs/wiki/pipeline_plugin_guidelines.md`），仓库内无 SDK 源码；默认插件为外部下载（`helm-charts/core/ci/base/values.yaml`） |
| 仓库内 API 文档 | GitLab/Jenkins 有成体系 API 文档 | `docs/apidoc/readme.md` 内容为 `# todo`；仅有 `support-files/apigw/bk_apigw_resources_devops.yaml` 与 `bk_apigw_docs_devops.zip` 机器可读定义 |
| 形式化规格 | — | `openspec/specs/` 仅 1 份规格（`version-name-deduplicate-postprocessor/spec.md`），`openspec/changes/archive/` 6 项变更，规格沉淀远小于代码规模 |

### 3.2 明显薄弱或需外部系统补齐

1. **CD/发布编排**：流水线内有制品归档与跨项目分发，但未见 GitLab 式 Release/Environment 部署实体与多环境晋级门禁（`core/process` 内仅有版本发布 `PipelineReleaseLock.kt`，属流水线版本而非应用发布）。
2. **测试覆盖**：`src/backend/ci` 共 7,757 个 `.kt`（约 93.2 万行），`src/test` 仅 213 个文件（约 4.19 万行，≈4.5%）；`core/artifactory`、`core/auth` 等模块测试为 0，`core/metrics` 1 个（统计来源：`find src/backend/ci -path "*src/test*" -name "*.kt"`）。
3. **生态依赖外部**：CodeCC（代码检查）、BK-Repo（制品存储）、BK-Turbo（编译加速）、蓝鲸 IAM（登录鉴权）——`docs/overview/installation.md` 明确"独立部署不包含登录鉴权、BK-REPO、CodeCC 等系统"。
4. **单体包功能面**：`boot-assembly/build.gradle.kts` 未引入 repository/metrics/ai/auth 的 biz 实现，若以单体方式部署，这些域需另行核实（Helm 部署不受影响）。
5. **多技术栈并存**：前端 Vue2.7/Vue3 双栈（`src/frontend/devops-pipeline/package.json` vs `devops-flow/package.json`）、YAML v2/v3 双版本（`common-pipeline-yaml/…/v2` 与 `…/v3`）、Java/Kotlin 混编（23 个 `.java`），演进中存在兼容负担（CHANGELOG 中大量 v2/v3 兼容修复）。

### 3.3 相对优势（GitLab CI/Jenkins 需额外搭建的部分）

- **企业级并发与配额**：项目/系统级构建配额、并发 group 与互斥（`JobQuotaBusinessService.kt`、`PipelineSetting.kt`、`MutexControl.kt`）。
- **多形态构建资源**：Docker/K8s/私有单机/私有集群/无编译环境统一调度（`BuildType.kt`、`dispatch/*`）。
- **质量红线 + 门禁回写**：规则/指标/拦截历史与 MR Check Run 联动（`core/quality`、`PipelineBuildCheckRunResolver.kt`）。
- **RBAC 细粒度权限**：项目/流水线/模板/凭证/环境等资源级授权（`AuthResourceType.kt` + `support-files/bkiam-rbac/`）。
- **矩阵并行、YAML 双模式、AI 助手**内置（`MatrixControlOption.kt`、`YamlPipelineEditor.vue`、`core/ai`）。

---

## 四、成熟度与风险

### 4.1 成熟度信号

| 指标 | 数值 | 证据 |
|---|---|---|
| 提交历史 | 41,821 次提交，131 位贡献者，首提交 2019-05-29 | `git log --oneline \| wc -l`、`git shortlog -sn --all \| wc -l` |
| 活跃度 | 最近提交 2026-10-19（调研前一日）；2026 年内 4,026 次提交 | `git log -5 --date=short`、`git log --since=2026-01-01 --oneline \| wc -l` |
| 版本 | release tag 至 `v4.2.0-rc.8`（2026-10-13），`git describe` = `v4.2.0-rc.8-209-g367b10e46fd`；构建版本由 `-Dci_version` 注入（默认 1.9.0） | `git tag`、`CHANGELOG/zh_CN/CHANGELOG-4.2.md`、`src/backend/ci/build.gradle.kts`、`.github/workflows/publishMavenJar4CI.yml` |
| 变更日志 | 连续大版本 1.13 → 2.0 → 3.0 → 3.2 → 4.0 → 4.1 → 4.2 | `CHANGELOG/zh_CN/` |
| 代码规模 | 后端 7,757 个 Kotlin 文件（≈93.2 万行）；Agent 255 个 Go 文件；前端 831 个 `.vue` + 421 个 ts/tsx | `find src/backend/ci -name "*.kt"`、`find src/agent -name "*.go"`、`find src/frontend -name "*.vue"` |
| 服务数 | 21 个 `boot-*` 微服务 + 单体 `boot-assembly` + 网关 + 前端 + Agent | `src/backend/ci/settings.gradle.kts`、`helm-charts/core/ci/templates/` |
| 工程化 | 7 条 GitHub Actions、License/漏洞扫描脚本、JOOQ 代码生成、分区表检查插件 | `.github/workflows/`、`src/backend/ci/license_check.sh`、`src/backend/ci/nvd_check_reports.sh`、`src/backend/ci/build.gradle.kts` |
| 测试 | 213 个测试文件 / 4.19 万行（≈4.5%） | `find src/backend/ci -path "*src/test*" -name "*.kt"` |

### 4.2 风险

1. **测试覆盖低**（≈4.5%，且集中在 `common`/`process`），回归主要依赖外部 CI（`.github/workflows/backend.yml`）与人工验证，重构风险高。
2. **外部依赖链长**：IAM、BK-Repo、CodeCC、Turbo、MySQL、Redis、ES、Consul/网关——最小可用集与完整能力集差距大（`docs/overview/installation.md`）。
3. **单体包与微服务包功能面不一致**（`boot-assembly/build.gradle.kts` 缺 repository/metrics/ai/auth biz）。
4. **文档滞后**：`docs/apidoc/readme.md` = `# todo`；`docs/install/linux.md` 仍描述 RabbitMQ/CentOS7/JDK8/Gradle6.7 环境；`docs/overview/code_framework.md` 中目录说明已与现状（缺少 ai/metrics/openapi 等）有出入。
5. **多版本兼容负担**：YAML v2/v3、V1/V2 模板、前端 Vue2/Vue3 并存，CHANGELOG 中持续出现跨版本兼容修复。
6. **插件生态外置**：默认插件仅 9 个且从 GitHub Release 下载（`helm-charts/core/ci/base/values.yaml`），离线/内网部署需自行搬运插件包。
7. **openspec 规格沉淀极少**（1 份 spec / 6 项变更），设计决策主要靠 CHANGELOG 与 PR 描述追溯。

---

## 五、总体判断

- **能否承担 CI 研发工作：能。** 编排（可视化 + YAML）、触发（6 类）、执行（多形态构建资源 + 配额排队）、控制（重试/取消/审核/并发/矩阵/条件）、集成（8 类代码源 + 制品 + 凭证 + 环境）、治理（权限 + 质量红线 + 度量 + 通知 + 审计）构成完整闭环，且有长期活跃的提交历史与可落地的镜像/Chart/单体包。
- **功能齐全度：CI 核心完整，CD 与开箱即用生态为短板。** 若要对标 GitLab CI/Jenkins 的"开箱即用"，需要补齐：构建缓存、里程碑类门禁、内置插件数量与 SDK 在仓化、API/规格文档、测试覆盖，以及 CodeCC/BK-Repo/IAM 等外部系统的配套部署。
