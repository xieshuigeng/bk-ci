# bk-ci 本地 Docker Compose 部署（v4.2.0-rc.7）

- 编排文件: `docker-compose.yml`（compose 项目名 `bkci`，网络 `bkci_bkci`，子网 172.28.0.0/16）
- 配置: `bkenv.properties`（渲染源）；后端使用 `rendered/etc/ci`（只读挂载到 `/etc/bkci/conf`）；
  网关/前端在容器启动时用镜像内 `render_tpl` 现场渲染
- 网关入口: http://localhost:8080 （`/` → 302 `/console/`）
- Consul UI: http://localhost:8500

## 重启后需执行清单

1. 启动基础设施与微服务（frontend/gateway 依赖 consul、dnsmasq）:

   ```bash
   docker compose up -d
   ```

2. **将 frontend 注册到 Consul**（必须在 gateway 启动/重启之前或紧接着执行）:

   ```bash
   ./register-frontend.sh
   ```

   网关对 `frontend.service.consul` 有一处静态 upstream（`frontend.conf` 中
   `proxy_pass http://frontend.service.consul;`），nginx **启动时**即用系统 DNS 解析该域名，
   依赖 Consul 中已有 `frontend` 服务记录。frontend 容器重建后 IP 会变化，需重新执行本脚本；
   若 gateway 在注册前启动会以 `[emerg] host not found in upstream` 退出并被
   `restart: unless-stopped` 自动重试，注册完成后会自行恢复。稳妥做法:

   ```bash
   ./register-frontend.sh && docker compose restart gateway
   ```

3. **清理 Consul 残留实例**（容器重建/重启后执行；旧实例 IP 失效会导致大量 502）:

   ```bash
   ./consul-cleanup.sh --dry-run   # 先看会删哪些
   ./consul-cleanup.sh
   ```

   背景：后端服务重启后会以新 IP 注册，但旧注册不会自动注销。网关按服务名解析时可能
   拿到已失效的旧 IP，表现为页面接口 `connect() failed (111: Connection refused)` 或
   `113: No route to host`，浏览器看到 `502 Bad Gateway`。脚本按“当前容器 IP”核对并只保留
   有效实例；可重复执行。`--dry-run` 仅打印不删除。

4. **初始化 bkrepo 平台账号**（首次部署或清空 `bkrepo-mongo-data` 后执行一次）:

   ```bash
   ./bkrepo-bootstrap.sh
   ```

   该脚本幂等写入平台账号 `bk_ci`（密钥 `devops`）与 bkrepo 超级管理员 `admin`。
   平台账号凭据必须与 `bkenv.properties` 中的
   `BK_CI_BKREPO_AUTHORIZATION="Platform YmtfY2k6ZGV2b3Bz"` 一致；
   值含空格，**必须加引号**，否则 `render_tpl` source 时会把它拆成命令并渲染为空。
   脚本使用空 `scopeDesc` 会缺少项目授权，已内置 `PROJECT PREFIX ""` 规则允许所有项目。

5. 验证:

   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/console/   # 期望 200
   ```

   建项目验证（应返回 `code:0`，且 `T_PROJECT` 出现记录）:

   ```bash
   curl -s -X POST http://localhost:8080/project/api/user/projects/ \
     -H 'Content-Type: application/json' -H 'X-DEVOPS-UID: admin' -H 'X-DEVOPS-TOKEN: devops' \
     -d '{"projectName":"demotest","englishName":"demotest","description":"demotest"}'
   ```

## 默认插件（已装 9/9）

已安装并设为默认：`checkout`、`run`、`SubPipelineExec`、`uploadArtifact`、
`uploadReport`、`AcrossProjectDistribution`、`downloadArtifact`、`PerforceSync`、
`CodeCCCheckAtom`。插件包内版本均为 `1.0.0`（仓库 release tag 不是插件版本号）。

`CodeCCCheckAtom` 官方仓库已删除（API/资产均 404），当前包由公开 fork
`huangjiao-heart/CodeCCCheckAtom` 源码构建：前端 Node 14 构建，后端用
`gradle:6.9-jdk8` 容器构建，并在 `task.json` 补 `releaseInfo`（logo 使用包内
`file/codeCC.png`，`frontendType=SPECIAL`）。该 fork 为 2021 年旧版（JDK8），
**仅验证了安装与默认标记，未验证流水线运行时兼容性**。

验证（经网关的 service 路由，需带服务 token）:

```bash
GW=http://localhost:8080
curl -s -H 'X-DEVOPS-TOKEN: devops' -H 'X-DEVOPS-UID: admin' \
  "$GW/store/api/service/pipeline/atom/codes/checkout/versions/1.0.0"
```

补装/重装插件（op 路由 `/auth/op` 需要登录 Cookie，脚本改为直连 store 容器）:

```bash
STORE_PORT=21918
code=checkout   # 换成目标 atomCode
docker cp /tmp/opencode/atoms/$code.zip bkci-store:/tmp/$code.zip
docker exec bkci-store curl -sS -XPOST "http://127.0.0.1:$STORE_PORT/api/op/pipeline/atom/deploy" \
  -H 'X-DEVOPS-UID: admin' -F atomCode=$code -F file=@/tmp/$code.zip
docker exec bkci-store curl -sS -XPOST "http://127.0.0.1:$STORE_PORT/api/op/pipeline/atom/default/atomCodes/$code" \
  -H 'X-DEVOPS-UID: admin'
```

列出已装插件:

```bash
docker exec bkci-store curl -sS \
  "http://127.0.0.1:21918/api/op/pipeline/atom/?page=1&pageSize=100" \
  -H 'X-DEVOPS-UID: admin'
```

## 本地部署对网关配置的适配（相对官方基线）

`docker-compose.yml` 中 gateway 启动命令在 `render_tpl` 之后做了两处 sed 修补，
`bkenv.properties` 末尾"Step10 网关→前端接线"段补充了若干变量，原因见各处注释，摘要:

| 问题 | 修复 |
|---|---|
| `__BK_CI_FRONTEND_HOST__` 官方基线未定义，渲染为空 → nginx `[emerg] no host in upstream ""` | `BK_CI_FRONTEND_HOST=frontend.service.consul` + 步骤 2 注册 |
| 大部分前端 location 经 `$frontendService`（=lua `config.kubernetes.domain`，硬编码 `kubernetes.demo.com`）转发 | gateway 命令中 sed 改为 `frontend.service.consul` |
| nginx `resolver`（变量型 proxy_pass 运行时解析）默认 `127.0.0.1:53` 无监听；仅指向 dnsmasq 又解析不了 compose 服务名（redis） | `BK_CI_GATEWAY_DNS_ADDR=127.0.0.11:53`（容器内 Docker 嵌入式 DNS，未知域名转 dnsmasq→consul） |
| 模板 `vhosts/devops.bkrepo.upstream.conf` 渲染出 `upstream { server ; }`（本地未部署 bkrepo） | 已部署拆分版 bkrepo 3.8.9-rc.2：`BK_REPO_FQDN=bkrepo.local`、`BK_REPO_GATEWAY_IP=172.28.0.63`（compose 静态地址） |
| bkrepo 要求 `Authorization: Platform base64(accessKey:secretKey)`，bk-ci 的 `BkRepoClient` 默认不带该头 | `bkenv.properties` 的 `BK_CI_BKREPO_AUTHORIZATION` 经网关 `set.bkrepo.conf` 注入；配合 `bkrepo-bootstrap.sh` |
| `BK_CI_LOGS_DIR` 在 `BK_HOME` 定义前求值成 `/logs/ci`，nginx 无法写日志 | 覆盖为 `/data/bkhome/logs/ci`，命令中 `mkdir -p && chmod 777`（worker 非 root） |
| lua redis 密码渲染为 `""`（非 nil，仍会 AUTH 报错） | 命令中 sed `pass = "",` → `pass = nil,` |
| lua `require()` 按进程 CWD 解析 `conf/lua/?.lua`，而命令 `cd /etc/bkci` 后启动 | 命令中 exec 前 `cd /usr/local/openresty/nginx`（其 conf 为指向 `/data/workspace/gateway/core` 的符号链接） |

Consul 域名: `BK_CI_CONSUL_DOMAIN=consul` 无需改 `service.consul`——dnsmasq 将 `/consul/`
转发给 consul DNS(172.28.0.10:8600)。`process.service.consul`、`frontend.service.consul`
**在 gateway 容器内**可解析（其 `dns: 172.28.0.53` → dnsmasq → consul DNS，nginx 启动时
解析 `frontend.service.consul` 即依赖此链路）；**后端容器内不经 DNS 解析这些域名**，后端走
Consul HTTP API（`consul:8500`，由 Docker 嵌入式 DNS 解析 `consul` 主机名）完成注册/发现
（Step 9.5 caveat 已验证不需要）。

## 当前状态（精简）
- 已完成：镜像构建、编排配置、渲染、wave A 全量启动、BkRepo 3.8.9-rc.2 打通建项目、9 个默认插件安装并验证
- 已完成：`dockerhost` + JDK17 构建镜像端到端验证；build #14 的 stage-1/2/3 全部成功，构建日志可在日志接口读取
- 已完成：UI 走查 3 项待办根因分析（2026-10-27）——「画布"?"」= 当初 API 造数据时**写入侧**编码丢失（库里名字节就是 `3F3F3F`，非前端问题）；「缺图标」= artifactory 静态 logo 未初始化（见排障节，已用 `deploy/local/fix-atom-logos.sh` 修复：9 个插件 + 31 个内置图标经网关校验全部 200，仅 tapd/scm 两个 SaaS 专属图标社区包未附带）；「详情页无返回键」= 前端 bug（`bk-breadcrumb` 的 `#prefix` 与 `back-router` 互斥，返回箭头恒不渲染）；「新建流水线只有模板/导入」= 上游设计（必须选已安装模板）+ 本地模板商店为空 → 立增强提案。详见 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md`「UI 走查问题清单」
- 操作提醒：用 API/curl 造含中文的数据前先 `export LC_ALL=C.UTF-8`（或 `PYTHONUTF8=1`）。宿主 charset 为 `ANSI_X3.4-1968` 时，脚本写模型 JSON 会把中文替换成 `?` 落库（前端只如实显示，服务端链路本身无损：JDK17 + `LANG=en_US.UTF-8` + JDBC `characterEncoding=utf8`）
- 注意：`CodeCCCheckAtom` 来自公开 fork，仅验证安装/默认标记，运行时兼容性未验证
- 已修复：后端 `/ms/project/api/user/locales/get` 返回 `zh_CN`，控制台启动脚本原样写入
  `window.INIT_LOCALE`，导致按 `zh_CN` 请求 `codelib/zh_CN.json` 等文件 404。现已在
  `frontend#console#index.html` 启动脚本中统一把下划线转为连字符（`zh_CN` → `zh-CN`）。

## 构建链路验证（2026-10-26）

- 流水线：`demotest` / `p-17fdae4c01774adaa693dc36c3872352`（`complex-demo-pipeline`）。
- 构建：`b-65889176dd294c0aa5a9591e499099ef`（#14），`status=0`，stage-1/2/3 全部 `SUCCEED`。
- 构建镜像：`127.0.0.1:5000/bkci/ci:jdk17`，由本地 registry 拉取；容器内 `java -version` 为 Temurin 17.0.19。
- 构建日志：日志服务恢复后已入库，初始化日志接口返回 330 行，含
  `build A on ...`、`build B on ...`、`run lint`、`run unit tests`。

触发与核对：

```bash
GW=http://localhost:8080
PROJECT=demotest
PIPELINE=p-17fdae4c01774adaa693dc36c3872352
curl -s -X POST -H 'Content-Type: application/json' -H 'X-DEVOPS-UID: admin' \
  -d '{}' "$GW/process/api/user/builds/$PROJECT/$PIPELINE"

docker exec bkci-mysql mysql -ubk_ci -pbk_ci123 -N -e \
  "select BUILD_ID,BUILD_NUM,STATUS,START_TIME,END_TIME from devops_ci_process.T_PIPELINE_BUILD_HISTORY \
   where PIPELINE_ID='$PIPELINE' order by BUILD_NUM desc limit 1;" 2>/dev/null

curl -s -H 'X-DEVOPS-UID: admin' -H 'X-DEVOPS-TOKEN: devops' \
  "$GW/log/api/user/logs/$PROJECT/$PIPELINE/<buildId>/?executeCount=1" | head -c 500
```

### 引擎不要与 process 同时运行

`boot-process` 已依赖 `biz-engine`，process 自身即可消费构建事件。再启动独立 `engine` 会让
同一组 START/stage 事件被两套消费者重复处理；取消构建时 `BuildIdLock` 的 1 秒重试会被放大，
曾造成 RabbitMQ 队列积压近 200 万条。当前 compose 已将 `engine` 放入 `legacy-engine` profile，
默认 `docker compose up -d` 不会启动它。**不要**用 `--profile legacy-engine` 启动，除非明确
修改了 process 的 engine 依赖。

`rendered/etc/ci/common.yml` 中的 `bkScs.consumer.concurrency.*: 1` 是额外的保护，避免单服务内
多消费者放大重试；重新渲染后需确认该段仍存在。

### RabbitMQ 重建后要重启日志服务

RabbitMQ 数据卷重建/账号变更后，`log` 服务的 AMQP 消费者会因认证失败停止且不会自动恢复，
表现为构建成功但详情页没有日志，队列 `default.build.log.*` 有积压且 `consumers=0`。处理：

```bash
docker restart bkci-log
sleep 20
docker exec bkci-rabbitmq rabbitmqctl list_queues -p bk_ci name messages consumers | grep default.build.log
```

确认消费者恢复（`consumers=5`、`messages=0`）后，历史日志事件会补消费并写入 ES。

### 原子/分类图标全部裂图（artifactory 静态文件未初始化）

现象：画布与插件卡片大量元素无图标。一条 curl 即可复现（HTTP 500 + `No such file or directory`）:

```bash
curl -s -H 'X-DEVOPS-UID: admin' -H 'X-DEVOPS-TOKEN: devops' \
  "http://localhost:8080/ms/artifactory/api/user/artifactories/file/download?filePath=%2Ffile%2Fpng%2FmanualTrigger.png&logo=true"
```

根因：本地 compose 未跑官方安装脚本 `docker-images/core/ci/ci-docker/scripts/bk-ci-setup.sh`，其 `setup_ci_artifactory()` 会把镜像内置 logo 静态文件复制进 artifactory 存储根（`cp -nrv "$BK_CI_SRC_DIR/support-files/file" "$BK_CI_DATA_DIR/artifactory/"`）。另一类是 9 个 zip 直装插件：其元数据 `logoUrl` 指向 `file/$<hash>.<hash>.png`，这些由官方发布流程上传，本地 `/api/op/pipeline/atom/deploy` 不上传图标（包内其实带图，如 `checkout/file/checkout.png`、`run/file/logo.png`）。

修复（幂等脚本，容器/数据卷重建后重跑）:

```bash
cd deploy/local && ./fix-atom-logos.sh      # ATOMS_DIR 默认 /tmp/opencode/atoms，可用环境变量覆盖
```

脚本做三件事：复制镜像内置 `support-files/file` 到存储根（层级必须是 `<存储根>/file/png/*.png`，浅一层仍 500）、按元数据 `logoUrl` **双重 URL 解码后**的文件名把包内图片落位、最后逐个经网关校验 HTTP 码。2026-10-27 执行结果：9 个插件 + 31 个内置原子/分类图标全部 200。

残留两点：`codeTapdWebHookTrigger`/`codeScmGitWebHookTrigger` 的 `tapdTrigger.png`、`scmGitTrigger.png` 社区包内并未附带（SaaS 专属），仍 500，表现为这两个触发元素无图标；另外前端 `bk-pipeline/src/Atom.vue:38` 只要 `logoUrl` 非空就用 `<img>` 且无 `@error` 回退到内置 sprite 图标，所以任何一个 500 都直接表现为"无图标"（改进见 `openspec/changes/add-atom-logo-load-fallback/`）。

### JVM 默认字符集是 ASCII（镜像内 LANG 指向不存在的 locale）

镜像 ENV `LANG=en_US.UTF-8`，但镜像内只装了 `C.utf8`（`locale -a` 可见），于是 JVM 退回
`file.encoding = native.encoding = ANSI_X3.4-1968`（`docker exec bkci-process java -XshowSettings -version | grep encoding` 可见）。
凡走 JVM 默认字符集的路径都会把中文降级为 `?`，属潜在隐患；已在 `docker-compose.yml` 的 `x-backend.environment`
统一改为 `LANG/LC_ALL=C.UTF-8`（改后两项均为 `UTF-8`，已重建 `process` 验证，构建 #16 正常）。

排查提醒：`mysql` 客户端不带 `--default-character-set=utf8mb4` 时会把库中**正确的** UTF-8 中文**显示**成 `?`；
判断是否真被写坏必须看字节，例如 `select hex(substring(TASK_NAME,1,4))`（UTF-8 中文形如 `E69E84`，真写坏则是 `3F`）。

## 已知限制

- `http://localhost:8080/` 的 302 Location 为 `http://localhost/console/`（nginx `rewrite ... redirect`
  生成的绝对 URL 不带非标端口），直接访问 `http://localhost:8080/console/` 即可。
- 已部署 bkrepo（gateway/auth/repository + 独立 mongodb），用于建项目时的制品库初始化。
- 未部署 codecc/agentless 等可选组件；`CodeCCCheckAtom` 插件由公开 fork 自行构建安装（9 个默认插件均已装），其运行时兼容性未验证。
- 模板商店为空（`GET /store/api/user/market/template/list` → `count:0`；项目侧 `GET /process/api/user/pipeline/template/v2/<project>/allTemplates`
  → `2101034 模板不存在`）。而新建流水线页面必须选中一个已安装模板才可提交（`CreatePipeline.vue:368-369`），故 UI 上只能"导入"；空白新建请用 API：
  `POST /process/api/user/pipelines/{projectId}`（body 为流水线 `Model`）。
