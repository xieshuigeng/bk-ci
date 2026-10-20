# BK-CI 外部生态工具/系统依赖清单（基于仓库一手来源）

- 调研日期：2026-10-20
- 调研对象：`/home/xsg/aicode/bk-ci`（`git describe` = `v1.8.0-RC.142-22947-g367b10e46fd`，HEAD `367b10e46fd`）
- 一手来源：`support-files/templates/`、`support-files/bkenv.properties`、`scripts/bkenv.properties`、`helm-charts/core/ci/`、`docker-images/`、`docs/overview/`、`docs/install/`、`src/backend/`、`src/frontend/`
- 口径说明：所有结论附仓库内文件路径；版本要求以文档/配置中明确写出的为准。
- 开源属性、许可证合规要点与对接 A/B/C 二次开发分类见文末「六、开源属性与二次开发评估」。

---

## 一、结论先行

### 1.1 必需依赖最小集（不装跑不起来）

下列系统在**独立部署**形态下同时被多份源码配置与 Helm Chart 强制引用（`spring.datasource`/`spring.data.redis`/`spring.cloud.consul`/MQ binder 等），缺失则服务无法启动或核心链路不可用：

| 依赖 | 角色 | 证据 |
|---|---|---|
| **MySQL 5.7+** | 关系型主库（每微服务一个 schema，如 `devops_ci_process`） | `docs/install/linux.md:45`、`support-files/templates/#etc#ci#application-process.yml`、`helm-charts/core/ci/base/values.yaml:118` |
| **Redis 2.8+** | 缓存 + 分布式锁 | `docs/install/linux.md:44`、`support-files/templates/#etc#ci#common.yml:46-62` |
| **Elasticsearch 7.x** | 构建日志存储与检索（默认 `BK_CI_LOG_STORAGE_TYPE=elasticsearch`） | `docs/install/linux.md:46`、`scripts/bkenv.properties:294-295`、`support-files/templates/#etc#ci#common.yml` |
| **RabbitMQ 3.7+** | 核心事件总线，默认 MQ binder（`bkCiMqDefaultBinder: core-rabbit`） | `docs/install/linux.md:47`、`support-files/templates/#etc#ci#common.yml:14-44`、`helm-charts/core/ci/base/default_env.yaml` |
| **Consul 1.0+** | 微服务注册与发现（网关 lua 依赖其 DNS 做路由） | `docs/install/linux/consul.md`、`support-files/templates/#etc#ci#common.yml:7-13`、`docs/overview/architecture.md` |
| **OpenResty 1.17.8.2+** | 网关（登录鉴权、Consul 服务发现转发、限流） | `docs/install/linux/gateway.md:5`、`support-files/templates/gateway#core#*.conf`、`docker-images/core/ci/dockerfile/openresty.Dockerfile` |
| **Docker** | 构建机的容器化运行（Agentless / 容器调度 / 默认镜像） | `scripts/bkenv.properties:270-277`、`helm-charts/core/ci/base/values.yaml:83-88` |

> 说明：Helm Chart 默认会随包部署 MySQL/Redis/ES/RabbitMQ/InfluxDB 的 Bitnami 子 Chart（`helm-charts/core/ci/Chart.yaml`），因此 K8s 一键安装时不需外部准备这些，但**概念上仍是必需依赖**（关闭内置即须外接 `external*`）。Consul 与 OpenResty 由 bk-ci 自身镜像承载（`docker-images/core/ci/dockerfile/`），不在子 Chart 内。

### 1.2 可选 / 增强依赖

以下系统**不装时核心 CI 仍可运行**，但对应功能缺失或降级（`docs/overview/installation.md:3` 明确："独立部署不包含登录鉴权、BK-REPO、CodeCC 等系统"）：

| 依赖 | 缺失后果 | 证据 |
|---|---|---|
| **蓝鲸 IAM（权限中心）** | 无 RBAC，退化为 `auth.idProvider=sample`（无鉴权） | `support-files/templates/#etc#ci#common.yml:377-406`、`scripts/bkenv.properties:88`、`support-files/bkiam-rbac/` |
| **蓝鲸 PaaS / 登录 / ESB** | 无统一登录、无 ESB 通知与免登 | `support-files/templates/#etc#ci#common.yml:388`、`scripts/bkenv.properties:25-32`、`common-auth` 的 `IamEsbService.kt:52` |
| **BK-Repo 制品库** | 制品存本地磁盘（`artifactory.realm=local`），缺共享存储与统一制品入口 | `support-files/templates/#etc#ci#application-artifactory.yml:21`、`#etc#ci#common.yml:477-481`、`BkRepoClient.kt` |
| **BK-CodeCC 代码检查** | 质量红线无代码检查指标、无 CodeCC 插件 | `support-files/templates/#etc#ci#common.yml:413-421`、`common-codecc/CodeccApi.kt` |
| **BK-Turbo 编译加速** | 无编译加速（`turbo.enabled` 默认 false） | `helm-charts/core/ci/base/values.yaml:76-80,980`、`support-files/turbo/turbo-op-ci.sh` |
| **InfluxDB** | 第三方构建机性能指标上报不可用（默认关闭） | `scripts/bkenv.properties:288-289,425-436`、`helm-charts/core/ci/base/values.yaml:222-241` |
| **Kubernetes / BCS 容器集群** | 只能用 VM 构建机；无法用 K8s/BCS 调度构建容器 | `support-files/templates/#etc#ci#application-dispatch.yml:29-64`、`scripts/bkenv.properties:211-232` |
| **MongoDB** | 仅 Turbo/Quartz 需要（turbo 关闭时非必需，Chart 默认 false） | `helm-charts/core/ci/base/values.yaml:242-304`、`scripts/bkenv.properties:461-472` |
| **Pulsar / Kafka** | 默认用 RabbitMQ；仅在切换 MQ binder 时需要 | `support-files/templates/#etc#ci#common.yml:35-44`、`common-kafka/KafkaClient.kt` |
| **企业微信 / 腾讯云邮件 / 蓝鲸消息（CMSI/NOC）** | 对应通知渠道不可用 | `support-files/templates/#etc#ci#application-notify.yml:12-31`、`common-notify/.../NotifyType.kt` |
| **蓝鲸日志（BKLog）/ 蓝鲸监控（BKMonitor）** | 无日志采集/监控接入（默认关闭） | `helm-charts/core/ci/templates/bklog.yaml`、`bkmonitor.yaml`、`values.yaml:57-74` |
| **大模型服务（OpenAI 兼容 / 蓝鲸 AI 网关）** | AI 助手不可用（`ai.enabled` 默认 false） | `scripts/bkenv.properties:507-510,576-589`、`helm-charts/core/ci/base/values.yaml:1108`、`core/ai/` |
| **jFrog Artifactory** | 旧版制品/Docker registry 对接（已被 BK-Repo 取代，多为废弃项） | `scripts/bkenv.properties:401-446` |

### 1.3 关键判断依据

- `docs/overview/installation.md:3`：独立部署**不含**登录鉴权、BK-REPO、CodeCC。
- `docs/overview/installation.md:13`：规模化部署（含登录鉴权、BK-REPO、CodeCC）走蓝鲸 CI 套餐。
- `helm-charts/core/ci/base/values.yaml` 的 `init.*` 与子 Chart `enabled` 开关是"必需/可选"的配置级依据。
- `scripts/bkenv.properties:5-14` 明确 `BK_CODECC_*`、`BK_REPO_*`、`BK_IAM_*`、`BK_PAAS_*` 注释为"声明依赖, 蓝鲸环境下会自动填充, 其他环境无需填写"。

---

## 二、依赖清单表

### 2.1 基础设施依赖（Infrastructure）

| 依赖 | 类别 | 用途说明 | 必需/可选 | 集成方式 | 证据（文件路径） |
|---|---|---|---|---|---|
| MySQL / MariaDB | 基础设施 | 关系型主库，按微服务分库 | **必需** | Spring `spring.datasource` JDBC 连接；JOOQ 生成 PO | `docs/install/linux.md:45`、`docs/overview/architecture.md`、`support-files/templates/#etc#ci#application-*.yml`、`helm-charts/core/ci/base/values.yaml:118` |
| Redis | 基础设施 | 缓存、构建机信息、分布式锁 | **必需** | `spring.data.redis`（含 Sentinel 集群配置） | `docs/install/linux.md:44`、`#etc#ci#common.yml:46-62`、`scripts/bkenv.properties:197-210` |
| Elasticsearch | 基础设施 | 构建日志存储/检索 | **必需**（默认） | REST 客户端，`BK_CI_LOG_STORAGE_TYPE=elasticsearch`（可切 lucene） | `docs/install/linux.md:46`、`scripts/bkenv.properties:294-295,413-424` |
| RabbitMQ | 基础设施 | 核心消息总线（事件流转） | **必需**（默认 binder） | Spring Cloud Stream binder `core-rabbit`/`extend-rabbit`；`rabbitQuorumEnable` 开关 | `docs/install/linux.md:47`、`#etc#ci#common.yml:14-44`、`helm-charts/core/ci/base/default_env.yaml` |
| Consul | 基础设施 | 服务注册与发现（网关 lua 依赖其 DNS） | **必需** | `spring.cloud.consul.discovery`；网关 DNS 指向本机 consul | `docs/install/linux/consul.md`、`#etc#ci#common.yml:7-13`、`scripts/bkenv.properties:159-176` |
| mongodb | 基础设施 | Turbo/Quartz 数据存储 | 可选 | Chart 子依赖，默认 `enabled: false`；外接 `externalMongodb` | `helm-charts/core/ci/base/values.yaml:242-304`、`scripts/bkenv.properties:461-476` |
| Pulsar | 基础设施 | 消息总线备选（`pulsar` binder） | 可选 | Spring Cloud Stream binder，`default-binder` 可切换 | `#etc#ci#common.yml:35-44` |
| Kafka | 基础设施 | 消息总线备选/内部 SDK | 可选 | `common-kafka/KafkaClient.kt` | `src/backend/ci/core/common/common-kafka/src/main/kotlin/com/tencent/devops/common/kafka/` |
| InfluxDB | 基础设施 | 第三方构建机性能指标（agentMetrix） | 可选 | Chart 子依赖；`.agent.properties` 上报 | `helm-charts/core/ci/base/values.yaml:222-241`、`scripts/bkenv.properties:288-289,425-436` |
| OpenResty | 基础设施 | API 网关：鉴权、限流、Consul 路由转发 | **必需** | nginx + lua 脚本（gateway 模板） | `docs/install/linux/gateway.md:5`、`support-files/templates/gateway#core#*.conf`、`docker-images/core/ci/dockerfile/openresty.Dockerfile` |
| Nginx Ingress Controller | 基础设施 | K8s 下外部入口 | 可选 | Chart 子依赖 `nginx-ingress-controller.enabled`（默认 false） | `helm-charts/core/ci/base/values.yaml:28-31`、`Chart.yaml` |
| Kubernetes | 基础设施 | 部署平台 + 构建容器调度 | 可选（部署形态之一） | Helm Chart；`kubernetes.apiUrl/token` | `docs/install/kubernetes.md`、`#etc#ci#application-dispatch.yml:31-48`、`scripts/bkenv.properties:221-232` |
| Docker | 运行时 | 构建机容器、Agentless | **必需**（用容器构建时） | docker registry / daemon | `docs/overview/architecture.md`、`scripts/bkenv.properties:270-277,401-412` |
| 对象存储（S3/COS/MinIO） | 基础设施 | ——**未启用**（配置项已标废弃） | 可选/废弃 | `s3.*` 配置仍在模板，但 bkenv 标注"废弃, 待清理"；凭证类型仍保留 `COS_*` | `#etc#ci#common.yml:370-376`、`scripts/bkenv.properties:451-458`、`ticket/.../CredentialType.kt`（`COS_APPID_SECRETID_SECRETKEY_REGION`） |

### 2.2 蓝鲸生态依赖（BlueKing Ecosystem）

| 依赖 | 类别 | 用途说明 | 必需/可选 | 集成方式 | 证据（文件路径） |
|---|---|---|---|---|---|
| 蓝鲸 IAM / 权限中心（RBAC） | 蓝鲸生态 | 登录鉴权与 RBAC 权限模型 | 可选 | `auth.idProvider=sample/bk_login/client`；`common-auth-provider` 的 `rbac/`；Helm init Job 导入模型 | `#etc#ci#common.yml:377-406`、`scripts/bkenv.properties:88-89`、`support-files/bkiam-rbac/*.json`、`helm-charts/core/ci/templates/init/init.iam-rbac.yaml` |
| 蓝鲸 PaaS / 登录（bk_login/SSM） | 蓝鲸生态 | 统一登录、免登、用户/部门同步 | 可选 | `auth.bkloginUrl` → PaaS login API；网关 SSM token 校验 | `#etc#ci#common.yml:388`、`scripts/bkenv.properties:25-32,183-186`、`common-auth/.../AuthDeptServiceImpl.kt` |
| 蓝鲸 ESB / API 网关 | 蓝鲸生态 | 应用态调用（IAM 资源注册、CD 插件） | 可选 | `esb.code/secret` + `bk.paas.host`；`IamEsbService` | `#etc#ci#common.yml:408-411,429-431`、`common-auth-api/.../IamEsbService.kt:52` |
| BK-Repo 制品库 | 蓝鲸生态 | 制品/静态资源存储 | 可选 | `bkrepo.bkrepoApiUrl`；`BkRepoClient`/`DirectBkRepoClient`；Helm init Job 建 repo | `#etc#ci#common.yml:477-481`、`common-archive/.../BkRepoClient.kt`、`helm-charts/core/ci/templates/init/init.bkrepo.yaml` |
| BK-CodeCC 代码检查 | 蓝鲸生态 | 代码检查指标、质量红线门禁 | 可选 | `codecc.host` + CodeccApi；CodeCCCheckAtom 插件 | `#etc#ci#common.yml:413-421`、`common-codecc/.../CodeccApi.kt`、`core/quality/` |
| BK-Turbo 编译加速 | 蓝鲸生态 | 编译加速服务 | 可选 | `bk-turbo` 服务 + Mongo/Rabbit/Redis；Helm 默认不启用 | `helm-charts/core/ci/base/values.yaml:76-80,980-1028`、`support-files/turbo/turbo-op-ci.sh`、`scripts/bkenv.properties:47-50` |
| BK-BCS 容器管理 | 蓝鲸生态 | BCS 容器集群调度构建机 | 可选 | `bcs.enable/apiUrl/token` | `#etc#ci#application-dispatch.yml:50-64`、`scripts/bkenv.properties:211-220`、`dispatch/.../bcs/BcsJobService.kt` |
| 蓝鲸 ITSM | 蓝鲸生态 | 项目创建/更新审批回调 | 可选 | `itsm.url` → 蓝鲸 API 网关 | `#etc#ci#application-auth.yml:28-37`、`scripts/bkenv.properties:59-66` |
| 蓝鲸监控（BKMonitor） | 蓝鲸生态 | 服务监控/权限资源注册 | 可选 | `serviceMonitor.enabled`；`monitor.register/url/iamSystem` | `helm-charts/core/ci/templates/bkmonitor.yaml`、`#etc#ci#application-auth.yml:42-46`、`scripts/bkenv.properties:71-76` |
| 蓝鲸日志（BKLog） | 蓝鲸生态 | 日志采集（dataId） | 可选 | `bkLogConfig.enabled`（默认 false） | `helm-charts/core/ci/templates/bklog.yaml`、`values.yaml:57-68` |
| 蓝鲸消息（CMSI/NOC） | 蓝鲸生态 | 短信/语音/邮件/微信通知通道 | 可选 | `notify.emailChannel=blueking`；`CMSApi` 走 CMSI | `#etc#ci#application-notify.yml:13-14`、`notify/blueking/sdk/CMSApi.kt` |
| 蓝鲸 SOPS / TAPD（工单） | 蓝鲸生态 | TAPD 工单触发流水线 | 可选 | `TapdClient`/`TapdOauthService`；process 的 `tapd` webhook 配置 | `src/backend/ci/core/repository/biz-repository/.../sdk/tapd/TapdClient.kt`、`#etc#ci#application-process.yml`（tapd secret/webUrl） |
| Stream（蓝盾创作流） | 蓝鲸生态 | 创作流页面/报告/徽章，独立服务 | 可选 | `BK_CI_STREAM_URL/SCM_TYPE`；`stream.scmType` | `scripts/bkenv.properties:342-351`、`#etc#ci#application-metrics.yml:64`、`#etc#ci#application-process.yml:114` |
| 大模型 / LLM（OpenAI 兼容 / 蓝鲸 AI 网关） | 蓝鲸生态 | AI 助手 | 可选 | `BK_CI_AI_LLM_BASE_URL` / `BK_CI_GPT_GATEWAY` | `scripts/bkenv.properties:507-510,576-589`、`core/ai/`、`core/misc/biz-gpt/` |

### 2.3 代码托管平台依赖（Code Hosting）

| 平台 | ScmType | 用途 | 必需/可选 | 集成方式 | 证据 |
|---|---|---|---|---|---|
| Git（通用） | `CODE_GIT` | 代码拉取/触发 | 可选（按需） | git 凭证 + webhook | `common-api/.../enums/ScmType.kt`、`common-webhook/.../GitWebHookMatcher.kt` |
| SVN | `CODE_SVN` | 代码拉取/触发 | 可选 | SVN + webhook | `ScmType.kt`、`common-webhook/.../SvnWebHookMatcher.kt` |
| GitLab | `CODE_GITLAB` | 代码拉取/触发 | 可选 | API/OAuth + webhook | `ScmType.kt`、`common-webhook/.../GitlabWebHookMatcher.kt` |
| GitHub | `GITHUB` | 代码拉取/触发、PR/Issue 事件 | 可选 | GitHub App（appId/privateKey）+ webhook | `ScmType.kt`、`common-webhook/.../handler/github/`、`scripts/bkenv.properties:364-373` |
| 工蜂 TGit | `CODE_TGIT` | 腾讯工蜂代码托管 | 可选 | TGit webhook + API | `ScmType.kt`、`common-webhook/.../handler/tgit/`、`scripts/bkenv.properties:500`（`T_REPOSITORY_TGIT_TOKEN`） |
| Perforce (P4) | `CODE_P4` | P4 代码库 | 可选 | P4 webhook；PerforceSync 插件 | `ScmType.kt`、`common-webhook/.../handler/p4/`、`helm-charts/core/ci/base/values.yaml:106-107` |
| SCM（SCM 协议通用） | `SCM_GIT`/`SCM_SVN`/`SCM_P4` | 通用 SCM 抽象 | 可选 | 同上 | `ScmType.kt` |
| Coding / Gitee / Gerrit | 未见独立枚举 | —— | 不支持 | 无独立 ScmType | `ScmType.kt`（仅上列 9 项，无 coding/gitee/gerrit） |
| TAPD | 工单源（非 SCM） | TAPD 需求/缺陷触发 | 可选 | TapdClient + OAuth | `repository/.../sdk/tapd/` |

### 2.4 构建运行时依赖（Runtime / Toolchain）

| 依赖 | 用途 | 版本要求 | 证据 |
|---|---|---|---|
| JDK | 后端编译与运行 | 编译文档 `jdk: 1.8`；镜像已升级 **TencentKona 17**（`jdk.Dockerfile` / values `defaultImage.tag: jdk17`） | `docs/overview/source_compile.md:63`、`docs/install/linux.md:42`、`docker-images/core/ci/dockerfile/jdk.Dockerfile`、`helm-charts/core/ci/base/values.yaml:88` |
| Gradle | 后端构建 | **6.7** | `docs/overview/source_compile.md:65`、`docs/install/linux.md:43` |
| Maven 私库 | 依赖拉取/deploy | 可选 | `docs/overview/source_compile.md:74-79`（`MAVEN_REPO_URL`） |
| Node.js + yarn | 前端构建 | **nodejs 8.0.0+** | `docs/overview/source_compile.md:8`、`docs/install/linux/frontend.md` |
| Golang | Agent 编译 | **1.12** | `docs/overview/source_compile.md:33`、`docs/install/linux/agent.md` |
| JRE（构建机） | worker-agent 运行 | JRE 1.8（旧）/ jdk17（新 agent-package） | `docs/install/linux/agent.md`、`docker-images/core/ci/dockerfile/jdk.Dockerfile` |
| 操作系统（Agent 支持） | 构建机 OS | linux / windows / macos（其他未验证） | `docs/overview/source_compile.md:34`、`docs/install/linux/agent.md` |
| 操作系统（部署） | 服务端 OS | CentOS 7.x / Linux | `docs/install/linux.md:41` |
| Helm / K8s | K8s 部署 | Kubernetes 1.16+、Helm 3+ | `helm-charts/core/ci/README.md` |

### 2.5 通知渠道（Notification Channels）

| 渠道 | NotifyType | 通道实现 | 必需/可选 | 证据 |
|---|---|---|---|---|
| RTX | `RTX` | 蓝鲸消息（CMSI） | 可选 | `common-notify/.../enums/NotifyType.kt:31`、`notify/blueking/` |
| 邮件 | `EMAIL` | 蓝鲸消息 或 **腾讯云邮件服务** | 可选 | `NotifyType.kt:32`、`#etc#ci#application-notify.yml:14-18` |
| 微信 | `WECHAT` | 蓝鲸消息 | 可选 | `NotifyType.kt:33` |
| 短信 | `SMS` | 蓝鲸消息（CMSI） | 可选 | `NotifyType.kt:34`、`CMSApi.kt`（`SMS_URL`） |
| 企业微信 | `WEWORK` / `WEWORK_GROUP` | 企业微信 API（qyapi.weixin.qq.com）：应用/机器人 | 可选 | `NotifyType.kt:35-36`、`#etc#ci#application-notify.yml:27`、`scripts/bkenv.properties:51-54,324-327` |
| 语音 | `VOICE` | 蓝鲸消息（CMSI） | 可选 | `NotifyType.kt:37`、`CMSApi.kt`（`VOICE_URL`） |
| 腾讯云邮件 | —— | 腾讯云 SES（secretId/secretKey/region） | 可选 | `#etc#ci#application-notify.yml:15-18`、`scripts/bkenv.properties:328-335` |

**通道选择**：企业微信 `weworkChannel: weworkAgent | blueking`；邮件 `emailChannel: blueking | tencentCloud`（`#etc#ci#application-notify.yml:13-14`、`scripts/bkenv.properties:326-329`）。

---

## 三、版本要求汇总（文档/配置中明确写出的）

| 组件 | 明确版本 | 来源 |
|---|---|---|
| MySQL | 5.7（文档）；Chart 8.0.37-debian-12-r2 | `docs/install/linux.md:45`；`helm-charts/core/ci/base/values.yaml:120` |
| Redis | 2.8.17（文档） | `docs/install/linux.md:44` |
| Elasticsearch | 7.4（文档）；Chart 17.5.4（bitnami） | `docs/install/linux.md:46`；`Chart.yaml` |
| RabbitMQ | 3.7.15（文档）；Chart 3.10.8-debian-11-r4 + `rabbitmq_delayed_message_exchange` 插件 | `docs/install/linux.md:47`；`values.yaml:183,191` |
| Consul | 1.0+ | `docs/install/linux/consul.md`、`docs/install/linux.md:48` |
| OpenResty | 1.17.8.2+（文档）；镜像用 1.19.9.1 | `docs/install/linux/gateway.md:5`；`docker-images/core/ci/dockerfile/openresty.Dockerfile` |
| InfluxDB | 1.8.3-debian-10-r88 | `helm-charts/core/ci/base/values.yaml:225` |
| MongoDB | bitnami 10.30.6 | `Chart.yaml` |
| Kubernetes / Helm | K8s 1.16+ / Helm 3+ | `helm-charts/core/ci/README.md` |
| JDK | 编译 1.8 → 运行 TencentKona 17.0.8 | `docs/overview/source_compile.md:63`；`jdk.Dockerfile` |
| Gradle | 6.7 | `docs/overview/source_compile.md:65` |
| Node.js | 8.0.0+ | `docs/overview/source_compile.md:8` |
| Golang | 1.12 | `docs/overview/source_compile.md:33` |
| Turbo 镜像 | bkci-turbo:0.0.21 | `values.yaml:985` |
| Chart / App | chart 1.16.1-beta2 / app 1.16.0 | `Chart.yaml` |

---

## 四、部署注意事项（缺依赖导致的功能不可用）

1. **独立部署 = 无鉴权**：`docs/overview/installation.md:3` 明确独立部署不含登录鉴权。默认 `BK_CI_AUTH_PROVIDER=sample`（`scripts/bkenv.properties:89`），即**任何人可访问、无 RBAC**；若要鉴权需接蓝鲸 IAM/PaaS。
2. **制品存储默认落本地盘**：默认 `BK_CI_ARTIFACTORY_REALM=local`（`scripts/bkenv.properties:339`）。多节点部署时 `artifactory.archiveLocalBasePath` 需共享存储（NFS/CephFS），不接 BK-Repo 则无统一制品入口与 Docker registry 集成（`#etc#ci#application-artifactory.yml:21-24`）。
3. **代码检查功能缺失**：不接 BK-CodeCC 则质量红线的代码检查类指标、CodeCCCheckAtom 插件不可用。
4. **无编译加速**：`turbo.enabled` 默认 false（`values.yaml:981`），不接 BK-Turbo 则无编译加速；启用 Turbo 还需 MongoDB + Redis + RabbitMQ（`scripts/bkenv.properties:459-490`、`values.yaml:242-304`）。
5. **容器构建能力依赖外部**：默认 `BK_CI_DOCKER_ROUTING_TYPE=VM`（`scripts/bkenv.properties:279`），K8s/BCS 构建机需显式开启并配置集群地址与 token（`#etc#ci#application-dispatch.yml:29-64`）。
6. **通知渠道默认依赖蓝鲸消息**：`emailChannel=blueking`（`application-notify.yml:14`），无蓝鲸环境需改 `tencentCloud` 或企业微信通道，否则邮件/短信/语音不可达。
7. **ES 内核参数**：内置 ES 需 `vm.max_map_count=262144`，否则启动报错（`docs/install/kubernetes.md:20`）。
8. **RabbitMQ 延迟插件必需**：事件流转依赖 `rabbitmq_delayed_message_exchange`（`values.yaml:191-192`），自建 MQ 需装该插件。
9. **Consul 是网关硬依赖**：网关 lua 按 `service.consul` 域名路由，缺失则全站不可访问（`docs/overview/architecture.md`、`#etc#ci#common.yml:7-13`）。
10. **默认插件从 GitHub 下载**：内置 9 个插件全部来自 `github.com/TencentBlueKing/ci-*`（`values.yaml:92-109`），离线环境需预置。
11. **优化/增强项默认关闭**：日志采集（BKLog）、监控（BKMonitor）、AI 助手、JWT、SM4 国密、审计均默认 false（`values.yaml:57-74,1108`、`scripts/bkenv.properties:395,131,236`）。
12. **对象存储未启用**：S3/COS 配置项已被标注废弃（`scripts/bkenv.properties:451-458`），当前制品不走对象存储；仅在凭证类型中保留 COS 枚举。

---

## 六、开源属性与二次开发评估

### 6.0 表前小结

- **调研方法（2026-10-20）**：许可证优先取一手来源——GitHub `/license` API、各仓库 LICENSE/README、官方 licensing 页面。蓝鲸系 10+ 仓库（`bk-iam`、`bk-monitor`、`bk-log`、`blueking-paas`、`bk-bcs`、`bk-sops`、`bk-itsm`、`bk-repo`、`bk-codecc`、`bk-turbo`）均为 TencentBlueKing 自定义格式 MIT License（API 与 License.txt 正文一手确认）。广泛使用的 Apache-2.0/MIT/BSD/GPL 项（K8s、Docker、Kafka、Pulsar、Gradle、Maven、Node.js、Go、Git、SVN 等）按各官方 LICENSE 链接列示（本次未逐一抓取正文，GitHub API 限流所致）。
- **总体结论：零开发即用**。39 个对接行中 **35 行 A 类（改配置即通）、2 行 B 类（扩展点，需适配开发）、2 行 C 类（废弃占位，需较大开发）**。bk-ci 对所有外部系统都是纯 API/Webhook 消费方：**外部系统侧一律零代码改动**（在 GitHub/TAPD/GitLab 控制台创建 App、配 webhook URL、开通 API 均属配置动作）；**bk-ci 侧**仅 B/C 项需要写代码。
- **许可证合规注意**：蓝鲸生态全系 MIT，可放心二次开发。但以下基础设施**不是**宽松 OSI 许可证，商用/分发前需评估：MongoDB（SSPL-1.0）、Consul（1.17+ BUSL-1.1，api/sdk 仍 MPL-2.0）、Elasticsearch（7.11+ SSPL/ELv2，7.10 及以前 Apache-2.0）、Redis（7.4+ RSALv2/SSPLv1，8.0+ 另含 AGPLv3，建议锁 ≤7.2）、MinIO（AGPL-3.0）。TAPD、工蜂、GitHub、Perforce、企业微信、腾讯云邮件为商业服务（无开源仓库）。仓库全量检索 `lighthouse|Lighthouse|灯塔` **无任何结果**——bk-ci 不含 Lighthouse 对接。
- **特别核实项确认**：(1) 代码平台 Webhook——外部平台只需把 bk-ci 的 webhook 地址填入平台侧配置，`common-webhook` 已有全套 handler（`docs/research/bk-ci-feature-inventory.md:40`），外部侧零开发；(2) GitHub App——`GithubService.kt` 消费 appId/privateKey（`scripts/bkenv.properties:364-373`），GitHub 侧创建 App 是控制台配置，非开发；(3) 默认插件从 GitHub 下载——Helm `plugin.enabled` 开启时按 `values.yaml:89-109` 的 URL 拉取 9 个 `TencentBlueKing/ci-*` 插件，离线环境属制品搬运/预置，非代码开发。

### 6.1 开源属性表（含对接分类与二次开发评估）

对接分类口径：**A 类** = 免开发（协议/标准集成，配置即通，bk-ci 已有完整客户端）；**B 类** = 有现成对接/扩展点但需适配开发（换环境要写代码）；**C 类** = 需较大二次开发或属占位/废弃项。

**基础设施**

| 依赖 | 开源? | 许可证 | 仓库/来源 | 对接（A/B/C） | 二次开发（bk-ci 侧 / 外部侧） | 证据 |
|---|---|---|---|---|---|---|
| MySQL / MariaDB | 是 | GPL-2.0(+FOSS Exception) / MariaDB GPL-2.0 | github.com/mysql/mysql-server、mariadb/server | A | 否 / 否 | `application-*.yml` spring.datasource |
| Redis | 是（源码可见） | ≤7.2 BSD-3-Clause；7.4+ RSALv2/SSPLv1；8.0+ 另含 AGPLv3 | github.com/redis/redis | A | 否 / 否 | redis.io/legal/licenses；`#etc#ci#common.yml:46-62` |
| Elasticsearch | 是（源码可见） | ≤7.10 Apache-2.0；7.11+ SSPL-1.0/Elastic License 2.0（2024 起+AGPLv3） | github.com/elastic/elasticsearch | A | 否 / 否 | elastic.co/licensing；`bkenv.properties:294-295` |
| RabbitMQ | 是 | MPL-2.0 | github.com/rabbitmq/rabbitmq-server | A | 否 / 否 | 仓库 LICENSE-MPL-RabbitMQ；`common.yml:14-44` |
| Consul | 是（源码可见，非 OSI） | ≤1.16 MPL-2.0；1.17+ BUSL-1.1（4 年后转 MPL；api/sdk 仍 MPL-2.0） | github.com/hashicorp/consul | A | 否 / 否 | hashicorp.com 博客；`common.yml:7-13` |
| MongoDB | 是（源码可见，非 OSI） | SSPL-1.0（2018-10-16 起） | github.com/mongodb/mongo | A | 否 / 否 | mongodb.com/legal/licensing；`values.yaml:242-304` |
| InfluxDB | 是 | 1.x MIT（Chart 固定 1.8.3）；上游主干（3.x）Apache-2.0 | github.com/influxdata/influxdb | A | 否 / 否 | GitHub /license；`values.yaml:222-241` |
| Pulsar | 是 | Apache-2.0 | github.com/apache/pulsar | A | 否 / 否 | `common.yml:35-44` |
| Kafka | 是 | Apache-2.0 | github.com/apache/kafka | A | 否 / 否 | `common-kafka/KafkaClient.kt` |
| OpenResty | 是 | BSD-2-Clause（套件聚合，各组件 BSD/MIT） | github.com/openresty/openresty | A | 否 / 否（网关模板 bk-ci 自带） | openresty.org；`gateway#core/*`、`openresty.Dockerfile` |
| Kubernetes / Nginx Ingress | 是 | Apache-2.0 | github.com/kubernetes/kubernetes、kubernetes/ingress-nginx | A | 否 / 否 | `application-dispatch.yml:31-48`、`values.yaml:28-31` |
| Docker（Moby） | 是 | Apache-2.0 | github.com/moby/moby | A | 否 / 否 | `bkenv.properties:270-277` |
| 对象存储（S3/COS/MinIO） | 混合：S3/COS 商业云服务；MinIO 开源 | MinIO AGPL-3.0；S3/COS 商业条款 | github.com/minio/minio、aws.amazon.com/s3、cloud.tencent.com/cos | **C** | **是**（配置已标废弃，若启用需恢复对象存储实现代码） / 否（提供 S3 兼容 API 即可） | `bkenv.properties:451-448`（"废弃. 待清理"）、`common.yml:370-376` |

**蓝鲸生态**

| 依赖 | 开源? | 许可证 | 仓库/来源 | 对接（A/B/C） | 二次开发（bk-ci 侧 / 外部侧） | 证据 |
|---|---|---|---|---|---|---|
| 蓝鲸 IAM（权限中心） | 是 | MIT | github.com/TencentBlueKing/bk-iam | A | 否 / 否（IAM 侧仅标准部署；资源模型由 bk-ci init Job 经 API 导入） | 仓库 License.txt（MIT）；`IamEsbService.kt:52`、`support-files/bkiam-rbac/` |
| 蓝鲸 PaaS / 统一登录 / ESB | 是 | MIT（含 legacy-bk-paas 的 ESB 组件） | github.com/TencentBlueKing/blueking-paas、legacy-bk-paas、blueking-apigateway | A（蓝鲸环境） | 否 / 否（填 URL/appcode 即通）；非蓝鲸 SSO 见 6.2 B 类 | README"基于 MIT 协议"；`common.yml:388,408-411`、`bkenv.properties:25-32` |
| 蓝鲸消息 CMSI（短信/语音/邮件/微信） | 是（随 PaaS ESB 交付） | MIT | legacy-bk-paas（compapi/v2/cmsi） | A | 否 / 否 | `notify/blueking/sdk/CMSApi.kt`（bkHost+URL） |
| BK-Repo 制品库 | 是（README 声明 MIT） | MIT | github.com/TencentBlueKing/bk-repo | A | 否 / 否 | `BkRepoClient.kt`、`init.bkrepo.yaml` |
| BK-CodeCC 代码检查 | 是（README 声明） | MIT | github.com/TencentBlueKing/bk-codecc | A | 否 / 否 | `CodeccApi.kt`、`common.yml:413-421` |
| BK-Turbo 编译加速 | 是 | MIT | github.com/TencentBlueKing/bk-turbo | A | 否 / 否 | 仓库 License.txt 全文；`turbo-op-ci.sh` |
| BK-BCS 容器管理 | 是 | MIT | github.com/TencentBlueKing/bk-bcs | A | 否 / 否 | `BcsJobService.kt` |
| 蓝鲸 ITSM | 是 | MIT | github.com/TencentBlueKing/bk-itsm | A | 否 / 否（ITSM 侧配 API/回调 URL 属配置） | `ItsmService.kt`（itsm.url、/operate_ticket） |
| 蓝鲸监控 BKMonitor | 是 | MIT | github.com/TencentBlueKing/bk-monitor | A | 否 / 否 | `bkmonitor.yaml`、`application-auth.yml:42-46` |
| 蓝鲸日志 BKLog | 是 | MIT | github.com/TencentBlueKing/bk-log | A | 否 / 否 | `bklog.yaml`、`values.yaml:57-68` |
| TAPD（工单触发） | 否（商业闭源 SaaS/商业私有部署） | 商业许可 | tapd.cn | A | 否 / 否（TAPD 侧建 OAuth 应用、开通开放平台 API 属配置/商务动作） | tapd.cn 服务协议；`TapdClient.kt`（注：并列提及的 SOPS 本身开源 MIT（bk-sops），但 bk-ci 仓库内无对接代码） |
| Stream（创作流） | **未核实**（TencentBlueKing 公开仓库清单无此仓库） | 未核实 | 未核实 | A（仅 URL 跳转对接） | 否（`BK_CI_STREAM_URL` 纯 URL 配置） / 外部侧需另行部署 Stream 服务 | `bkenv.properties:342-351`、`application-metrics.yml:64` |
| 大模型 / AI 网关 | 协议开源：OpenAI 兼容（自建可用 vLLM/Ollama 等）；蓝鲸 AI 网关本体未核实 | OpenAI 兼容 API | 自选（任意 OpenAI 兼容服务） | A | 否（langchain4j+openai4j 客户端已有） / 外部侧部署兼容服务（配置动作） | `AiLlmProperties.kt`、`HunYuanChatModel.kt`、`bkenv.properties:576-589` |

**代码托管平台**

| 依赖 | 开源? | 许可证 | 仓库/来源 | 对接（A/B/C） | 二次开发（bk-ci 侧 / 外部侧） | 证据 |
|---|---|---|---|---|---|---|
| Git | 是 | GPL-2.0-only | github.com/git/git | A | 否 / 否 | `ScmType.kt`、`common-webhook/.../GitWebHookMatcher.kt` |
| SVN | 是 | Apache-2.0 | github.com/apache/subversion | A | 否 / 否 | `SvnWebHookMatcher.kt` |
| GitLab（CE） | 是（CE；EE 商业） | MIT | gitlab.com/gitlab-org/gitlab-foss | A | 否 / 否（GitLab 侧配 OAuth 应用+webhook URL） | docs.gitlab.com/development/licensing |
| GitHub | 否（商业 SaaS，Microsoft） | GitHub 服务条款 | github.com | A | 否 / 否（GitHub 侧控制台创建 App，属配置非开发） | `bkenv.properties:364-373`、`GithubService.kt`、`common-webhook/.../handler/github/` |
| 工蜂 TGit | 否（腾讯商业） | 商业许可 | tgit.tencent.com | A | 否 / 否 | `common-webhook/.../handler/tgit/`、`bkenv.properties:500` |
| Perforce P4 | 否（商业，有免费版） | 商业许可 | perforce.com | A | 否 / 否 | `common-webhook/.../handler/p4/`、`PerforceSync` 插件 |

**工具链与通知渠道**

| 依赖 | 开源? | 许可证 | 仓库/来源 | 对接（A/B/C） | 二次开发（bk-ci 侧 / 外部侧） | 证据 |
|---|---|---|---|---|---|---|
| JDK / TencentKona | 是 | GPL-2.0-only WITH Classpath-Exception-2.0 | github.com/Tencent/TencentKona-17 | A | 否 / 否 | 仓库 LICENSE；`values.yaml:88` |
| 构建工具链（Gradle/Maven/Node.js/Go） | 是 | Apache-2.0（Gradle、Maven）；MIT（Node.js）；BSD-3-Clause（Go） | gradle/gradle、apache/maven、nodejs/node、golang/go | A | 否 / 否 | `docs/overview/source_compile.md:8,33,65,74-79` |
| 企业微信 | 否（腾讯商业 SaaS） | 商业服务条款 | work.weixin.qq.com | A（应用通道 weworkAgent） | 否 / 否（企微侧建应用拿 secret 属配置）；机器人通道 `weworkRobot` 注释"待开放"即未实现，若需机器人通道属 B | `application-notify.yml:13`、`WeworkServiceImpl.kt` |
| 腾讯云邮件（SES） | 否（腾讯云商业服务） | 商业条款 | cloud.tencent.com | A | 否 / 否 | `TencentCloudEmailConfiguration.kt`（emailChannel=tencentCloud） |
| 自定义通知渠道（扩展点） | n/a（bk-ci 扩展点） | n/a | bk-ci 扩展点：`NotifyType` 枚举固定 | **B** | **是**（新增 NotifyType 枚举值+发送实现类） / n/a | `NotifyType.kt:31-37`（7 种固定）、`application-notify.yml:13-14` |
| 非蓝鲸 SSO 登录鉴权（扩展点） | n/a（bk-ci 扩展点） | n/a | bk-ci 扩展点：网关 lua + idProvider | **B** | **是**（新增 `auth_user-<provider>.lua`+后端 idProvider 实现） / 外部 IdP 支持标准协议即可 | `auth.conf`（`auth_user-__BK_CI_AUTH_PROVIDER__.lua`）、`src/gateway/core/lua/auth/`（5 个现成实现）、`MockAuthAutoConfiguration.kt`/`RbacAuthAutoConfiguration.kt`（后端仅内置 sample/rbac） |
| jFrog Artifactory（旧制品对接） | 否（商业，有免费版） | 商业许可 | jfrog.com | **C** | **是**（已被 BK-Repo 取代，仅残留配置，恢复需较大开发） / 否 | `bkenv.properties:338-339`（`ARTIFACTORY_REALM=local\|bkrepo`）、`:403,437-446`（`BK_CI_JFROG_*`） |

### 6.2 对接 A/B/C 分类表

| 类别 | 计数 | 依赖清单 | 结论 |
|---|---|---|---|
| **A 类 · 免开发** | **35** | MySQL、Redis、ES、RabbitMQ、Consul、MongoDB、InfluxDB、Pulsar、Kafka、OpenResty、K8s/Ingress、Docker、IAM、PaaS/ESB/统一登录、CMSI、BK-Repo、BK-CodeCC、BK-Turbo、BK-BCS、ITSM、BKMonitor、BKLog、TAPD、Stream（URL）、LLM/OpenAI 兼容、Git、SVN、GitLab、GitHub、工蜂、P4、Kona JDK、构建工具链、企业微信、腾讯云邮件 | 协议/标准集成，bk-ci 已有完整客户端；改配置即通，**bk-ci 侧与外部侧均零开发**（外部侧的建 App/配 webhook/开通 API 属配置动作） |
| **B 类 · 扩展点需适配开发** | **2** | ① 自定义通知渠道（`NotifyType` 枚举固定 7 种，新增渠道需改代码；`weworkRobot` 机器人通道"待开放"）；② 非蓝鲸 SSO 登录鉴权（网关 `auth_user-*.lua` 参数化选择，后端 idProvider 仅内置 sample/rbac，对接其他 SSO 需新写 lua+Kotlin 实现） | bk-ci 提供扩展点与现成示例实现，换环境/换产品要写代码；**外部侧仍零代码** |
| **C 类 · 废弃占位/需较大开发** | **2** | ① 对象存储 S3/COS/MinIO（`bkenv.properties:451-448` 标"废弃. 待清理"，制品默认本地盘/BK-Repo，若启用需恢复实现代码；注意 MinIO 为 AGPL-3.0）；② jFrog Artifactory（旧制品/Docker registry 对接，已被 BK-Repo 取代，仅残留 `BK_CI_JFROG_*` 配置） | 均为历史遗留项；如确需使用，bk-ci 侧需较大二次开发，外部侧零开发 |

补充说明：AI 网关、Stream、GitHub/Gitee/Coding 等无法从仓库内查证的开源状态已按「未核实」标注；仓库内不存在 Lighthouse 对接（全量检索无结果）。
