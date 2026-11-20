# bk-ci 设备迁移交接（2026-11-20）

**TL;DR**：本机仓库 `master` 相对上游 `origin/master` 超前 90 个提交，工作区仍有 1 个已修改文件（`deploy/local/README.md`）与 2 个未跟踪文件（反代脚本、恢复计划）；2026-11-19 的「恢复与验证」5 个 Task 实际只完成了 Task 2 的本机文件改动（README 旧 IP 改 `172.28.0.77`、新增 `pipeline-dev-proxy.js`，且未提交），其余均未完成或无法证实，当前除 `bkci-bkrepo-repository` 处于重启循环外，主要 `bkci-*` 容器均已停止、8080/8500/8006/8088/5000 端口均不可达。迁移包 `/home/xsg/aicode/bkci-local-stash` 在仓库外、5.4G、192 项 SHA256 校验全部通过，但缺 8 个官方插件 zip 与 CodeCC 重构建包；两个 openspec 变更的实现已提交（`2255681`），验证项 3.1–3.4 / 4.1–4.5 全部未勾选、未归档。新机必须先带走迁移包与仓库内未提交内容，把 upstream 改到 `mine` 后再按本文件第四、五节恢复与验证。

---

## 一、昨天（2026-11-19）实际发生了什么

| 时间（本机 +08） | 事件 | 证据 |
|---|---|---|
| 2026-11-02 11:50 | 提交 `2255681`：AtomLogo 图标回退 + 空白创建流水线入口。实现已入库，但**不在 release 前端镜像中、未做浏览器验证** | `git log`；`deploy/local/README.md:143`；`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:161`、`:171`、`:179-180` |
| 11-19 09:28 | 提交 `7ead01d7130`：consul 静态 IP 从 `172.28.0.10` 改为 `172.28.0.77`，规避 DHCP 抢占与 IPAM 残留 | `git log -5 --format`；`deploy/local/docker-compose.yml:131-134`；`deploy/local/docker-compose.yml:144` |
| 11-19 09:31 | `/tmp/opencode/handoff-bkci-machine-switch.md` 生成，记录换机顺序；其中称多数容器已 `Exited (137)` 约 8 天 | 文件 mtime（现场 `stat`）；`/tmp/opencode/handoff-bkci-machine-switch.md:6-9`、`:32-38` |
| 11-19 09:55–10:18 | 导出迁移包到仓库外 `/home/xsg/aicode/bkci-local-stash`；来源提交记为 `7ead01d7130`，已推送 fork `mine/master` | stash 各目录 mtime（现场 `stat`）；`/home/xsg/aicode/bkci-local-stash/README.md:5`、`/home/xsg/aicode/bkci-local-stash/manifest.txt:2-6` |
| 11-19 10:51 | 两个 openspec `tasks.md` 末尾追加「验证状态（2026-11-19）」：明确 3.1–3.4 / 4.1–4.5 **未勾选**，并写明前置与逐条验证口径 | 文件 mtime（现场 `stat`）；`openspec/changes/add-atom-logo-load-fallback/tasks.md:22-32`；`openspec/changes/add-blank-pipeline-creation-entry/tasks.md:28-39` |
| 11-19 10:54 | 提交 `5e9490c3c0b`：对账部署/前端计划状态、openspec 验证待办写实，未提上游 PR | `git log -5 --format`；`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:307-316`；`docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1306-1313` |
| 11-19 11:11 | 新建未提交计划 `docs/superpowers/plans/2026-11-19-restore-and-verify.md`，5 个 Task 的 31 个复选框全部保持未勾选 | 文件 mtime（现场 `stat`）；`docs/superpowers/plans/2026-11-19-restore-and-verify.md:30-324` |
| 11-19 约 11:12–11:26 | 多数容器被再次启动过（`bkci-frontend` 起于 03:12:12Z、`bkci-mysql` 03:12:29Z、`bkci-consul` 03:21:20Z、`bkci-process` 03:25:04Z、`bkci-gateway` 03:26:09Z），但**没有留下健康检查或验证记录** | 现场 `docker inspect .State.StartedAt`；计划中的验证步骤见 `docs/superpowers/plans/2026-11-19-restore-and-verify.md:32-74` |
| 11-19 17:35 | 下午实际留下两项文件改动：`deploy/local/README.md:128` 的旧 consul IP 改为 `172.28.0.77`；新建 `deploy/local/pipeline-dev-proxy.js`（内容与计划给出的脚本一致）。二者**均未提交** | 两文件 mtime（现场 `stat`）；`git diff -- deploy/local/README.md`；`docs/superpowers/plans/2026-11-19-restore-and-verify.md:84-144` |
| 11-19 约 18:11 | 主要 `bkci-*` 容器几乎同时停止：`bkci-process`/`gateway`/`frontend`/`mysql` 均 `Exited (137)`、`OOMKilled=false`，`bkci-consul` `Exited (1)`；`bkci-process` 累计重启 662 次；`bkci-bkrepo-repository` 处于重启循环（曾重启 1266 次） | 现场 `docker ps -a`、`docker inspect .State` |
| 11-20 调查时 | `ss -ltn` 显示 8080/8500/5000/8006/8088 均未监听；`curl` 这些端口返回 `000`；无 webpack / dev server / proxy 进程；`/tmp/opencode` 只剩上述 handoff 文件，无 `pipeline-dev.log` / `pipeline-proxy.log` / pid 文件 | 现场 `ss -ltn`、`curl`、`ps aux`、`ls -la /tmp/opencode` |

补充事实（低优先级）：`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:25` 与 stash `README.md:45` 都写「`/tmp/opencode` 已清空」，但现场仍存在 09:31 生成的 handoff 文件；它只能作为线索，不能替代仓库内已提交的计划与续节。

---

## 二、当前计划与真实状态

### 2.1 `2026-11-19-restore-and-verify.md` 五个 Task 的真实状态

> 判断原则：复选框全是未勾选（`docs/superpowers/plans/2026-11-19-restore-and-verify.md:32-324`），但复选框不等于现实；下表以文件 mtime、`git diff`、容器/端口/进程现场为准。

| Task | 状态 | 证据与说明 |
|---|---|---|
| Task 1 原地恢复 Docker 并健康检查 | **未做（当前不健康）** | 计划要求 `docker compose up -d`、注册 frontend、consul 清理、`console:200`（`:30-74`）。现场：主要容器全部停止、8080/8500 无监听、无检查记录；stash 导出时也已写明「多数容器已停止」（stash `README.md:11`）。中午曾被启动过，但无法证明通过健康检查。 |
| Task 2 README 旧 IP + 持久化反代脚本 | **部分完成（仅本机文件）** | README IP 已改为 `172.28.0.77`（`deploy/local/README.md:128`，`git diff` 可见；计划 `:84-86`）；`deploy/local/pipeline-dev-proxy.js` 已存在且与计划脚本一致（计划 `:88-144`），现场 `node --check` 通过、`git diff --check` 无输出。未提交、未纳入版本控制（`git status` 显示 `M` 与 `??`）。 |
| Task 3 补回 8 个插件 zip 到迁移包 | **未做** | 现场 `stash/extras/atoms/` 目录不存在；`stash/SHA256SUMS` mtime 仍是 10:18，未重算；stash `README.md:45`、`:128` 与 `manifest.txt:19` 明确插件 zip 与 dev proxy 未包含。计划的下载/提取/重算步骤见 `:158-202`。 |
| Task 4 dev server + 反代 + 自动化验证 | **未做（无证据）** | 现场无 `npm run dev` / node 反代进程，端口 8006/8088 关闭，`/tmp/opencode` 无日志与 pid；计划要求的 `devserver:200` / `proxy-console` 等记录（`:206-252`）不存在。`src/frontend/frontend/pipeline` 中虽有含 `AtomLogo` / `hasUsableTemplate` 的产物，但 mtime 为 2026-11-02，属旧 dev 构建残留，不能当作 11-19 的运行证据。 |
| Task 5 记录结果、归档门控与提交 | **未做** | 计划 `:256-324` 全部未勾选；`grep` 未发现 `### 2026-11-19 恢复与验证` 续节（部署主计划止于 `:1306-1313` 的对账节）；两个 openspec 验证项仍原样未勾选；`archive/2026-11-19-*` 不存在；`git log` 最新仍是 10:54 的 `5e9490c3c0b`。 |

### 2.2 前端 openspec 验证状态

| 变更 | 实现 | 验证 | 归档 |
|---|---|---|---|
| `add-atom-logo-load-fallback` | 1.1–1.4、2.1–2.3、3.5 已勾选（`openspec/changes/add-atom-logo-load-fallback/tasks.md:3-20`），代码来自提交 `2255681` | 3.1–3.4 未勾选（`:16-19`）；`:22-32` 写明原因是镜像不含 `AtomLogo`、当前部署未重建，前置为新机 dev server `:8006` + 反代 `:8088` | 未执行；门控要求四项全通过后才 `mv` 到 `archive/` 并写 `.openspec.yaml`（`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:243-262`） |
| `add-blank-pipeline-creation-entry` | 1.1–3.2 已勾选（`openspec/changes/add-blank-pipeline-creation-entry/tasks.md:3-18`），代码来自提交 `2255681` | 4.1–4.5 未勾选（`:22-26`）；`:28-39` 写明缺已安装模板项目、无第二个有权限用户，需 dev server + `:8088` 验证 | 未执行；同上门控（`:285-308`） |

两个变更的提案本身分别说明了动机与验证要点：`openspec/changes/add-atom-logo-load-fallback/proposal.md:3-10`、`:28-34`；`openspec/changes/add-blank-pipeline-creation-entry/proposal.md:3-14`、`:33-39`。两个活动变更目录被 `.gitignore:68` 忽略，现场 `git ls-files` 确认未跟踪；不得 `git add -f`，须验证通过后移入 `archive/` 再纳入版本控制（`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:204`）。

---

## 三、迁移到新设备的整体计划

1. **先保住资产**：完整复制 `/home/xsg/aicode/bkci-local-stash`（5.4G，仓库外），另备 fork SSH key；仓库内把 `M`/`??` 三项提交或原样拷贝（第六节）。
2. **修正远端指向**：新机 clone `mine` 后 `git branch --set-upstream-to=mine/master master`（stash `README.md:62-65`）。当前本机 upstream 仍是 `origin/master`（现场 `git rev-parse --abbrev-ref @{upstream}`），只有 `mine` 是个人 fork（`git remote -v`），不要 `git push origin`。
3. **备好前置**：Docker 24 + Compose v2、Node 22 + npm、约 20G 可用磁盘、端口 80/8080/8088/8500/5000/8006 空闲、静态 IP `172.28.0.77` 可用（stash `README.md:47-53`）。新机当前 248G 可用，迁移包实际 5.4G（现场 `df -h`、`du -ah`）。
4. **按第四节恢复镜像、registry、数据卷、配置与宿主机绑定数据**，先不重建镜像（stash `README.md:68-106`）。
5. **启动与注册**：`docker compose up -d` → `register-frontend.sh` → consul 清理 → 重启 gateway，并做 console / Consul 健康检查（stash `README.md:108-125`；`deploy/local/README.md:9-61`）。
6. **按需补 bkrepo bootstrap、插件与图标修复**（第四节的 4.6/4.7）。卷已恢复时 9 个默认插件应在库里；只有重装/补图标才需要 zip（`deploy/local/README.md:71-75`、`:194-213`）。
7. **起 dev server + `:8088` 反代**，逐条执行 3.1–3.4 / 4.1–4.5 浏览器验证，截图写入 `stash/extras/verification-screenshots/`（`docs/superpowers/plans/2026-11-19-restore-and-verify.md:265-279`）。
8. **只有全部通过后**才归档两个 openspec、追加部署计划续节、提交并推送 `mine/master`（`:281-324`）；否则如实保留未勾选并把新机验证结论写回交接文档。

---

## 四、如何部署（从零 / 从 stash 恢复）

以下命令主体来自 stash `README.md:55-155` 与 `deploy/local/README.md`，`$STASH` = `/home/xsg/aicode/bkci-local-stash`，`$REPO` = 新机仓库路径。命令块中不含解释性注释，前置条件与注意事项写在命令块前后。

### 4.0 前置与约束

- Docker 24 + Compose v2、Node 22 + npm；端口 80、8080（网关）、8088（dev 反代）、8500（Consul）、5000（本地 registry）、8006（webpack）需空闲（stash `README.md:49-51`）。
- 子网 `172.28.0.0/16`、网关 `172.28.0.1`；consul 固定 `172.28.0.77`、dnsmasq `172.28.0.53`、bkrepo auth/repository/gateway 分别 `172.28.0.61/.62/.63`（`deploy/local/docker-compose.yml:3-9`、`:131-150`、`:342`、`:373`、`:416`）。新机若这些地址被占用，必须先释放或同步改 compose 与 dnsmasq `--server`（`deploy/local/docker-compose.yml:144`；stash `README.md:52-53`）。
- `engine` 保持在 `legacy-engine` profile，**不要**用 `--profile legacy-engine` 启动，否则与 process 重复消费构建事件（stash `README.md:127`；`deploy/local/README.md:170-179`）。
- 整机 IP 变化时需改 `bkenv.properties` 的 `BK_DOMAIN` / `BK_CI_PUBLIC_URL` / `BK_CI_PRIVATE_URL` 并重新渲染、force-recreate、重新注册 frontend（stash `README.md:136-142`；重渲染命令见 4.9）。

### 4.1 代码（stash README 4.1）

```bash
git clone ssh://git@ssh.github.com:443/xieshuigeng/bk-ci.git "$REPO"
cd "$REPO" && git checkout 7ead01d7130
git branch --set-upstream-to=mine/master master
git status -sb
```

来源：stash `README.md:59-66`。`git status -sb` 应为 clean；本机的未提交改动见第六节，若希望新机也带上，先提交或拷贝后再执行 checkout。

### 4.2 导入镜像与本地 registry（stash README 4.2）

```bash
docker load -i "$STASH/images/bkci-images.tar.gz"
docker images | grep -E 'bkci-local|bkci/ci|bkrepo'
docker run -d --name bkci-registry --restart=always -p 5000:5000 dockerproxy.net/library/registry:2
docker push 127.0.0.1:5000/bkci/ci:jdk17
```

来源：stash `README.md:68-77`。打包的 19 个镜像清单见 stash `images/image-list.txt:1-19`，其中包含 `bkci-local/bkci-{backend,frontend,gateway}:v4.2.0-rc.7`、bkrepo 三件套、`127.0.0.1:5000/bkci/ci:jdk17`、`dockerproxy.net/library/registry:2`、`alpine:latest`。构建资源使用本地 registry 是硬依赖（stash `README.md:74-76`）。

### 4.3 导入四个数据卷（stash README 4.3）

若新机已有同名容器，先在 `$REPO/deploy/local` 执行 `docker compose down`，**不要加 `-v`**（stash `README.md:82`）。卷名为 `bkci_mysql-data`、`bkci_consul-data`、`bkci_bkrepo-mongo-data`、`bkci_rabbitmq-data`（stash `README.md:24-28`、`manifest.txt:10`）。

```bash
for v in bkci_mysql-data bkci_consul-data bkci_bkrepo-mongo-data bkci_rabbitmq-data; do
  docker volume create "$v"
  docker run --rm -v "$v:/data" -v "$STASH/volumes:/backup" alpine:latest \
    sh -c "tar xzf /backup/$v.tar.gz -C /data"
done
```

来源：stash `README.md:79-88`。若不需要旧项目/构建数据可跳过本节走重建路线（stash `README.md:130-134`）。

### 4.4 还原配置与附属数据（stash README 4.4）

```bash
cp -a "$STASH"/config/{bkenv.properties,bkrepo.env,bkrepo.env.fixed,bkrepo-consul-services.json} "$REPO/deploy/local/"
cp -a "$STASH/config/rendered"          "$REPO/deploy/local/"
cp -a "$STASH/config/bkrepo-etc.rendered" "$REPO/deploy/local/"
cp -a "$STASH/extras/bkrepo-work/."     "$REPO/deploy/local/"
mkdir -p /data/bkci-local && cp -a "$STASH/extras/host-data-bkci-local/." /data/bkci-local/
mkdir -p "$REPO/deploy/local/extra-jars" && cp -a "$STASH/extras/extra-jars/." "$REPO/deploy/local/extra-jars/"
```

来源：stash `README.md:90-99`。这些文件含明文凭据，必须保持私密（stash `README.md:174`；第五节）。仅当需要重新构建镜像时才解包构建上下文：

```bash
cp -a "$STASH/artifacts/bkci-slim.tar.gz" "$REPO/"
tar -xzf "$STASH/artifacts/ci-docker.tar.gz" -C "$REPO/docker-images/core/ci/"
```

来源：stash `README.md:101-106`。

### 4.5 启动、注册与验证（stash README 4.5 + deploy README 重启清单）

```bash
cd "$REPO/deploy/local"
docker compose up -d
./register-frontend.sh
./consul-cleanup.sh --dry-run && ./consul-cleanup.sh
docker compose restart gateway
docker compose ps
curl -s -o /dev/null -w "console:%{http_code}\n" http://localhost:8080/console/
curl -s http://localhost:8500/v1/agent/services | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print(len(d), 'services registered')"
```

来源：stash `README.md:108-125`；`deploy/local/README.md:9-43`、`:57-61`。期望 `console:200`（或 302）、注册服务数 >0、无 `engine` 容器。frontend 必须在 gateway 启动/重启前后重新注册，否则 nginx 启动时解析 `frontend.service.consul` 失败（`deploy/local/README.md:17-31`）；稳妥命令是 `./register-frontend.sh && docker compose restart gateway`（`deploy/local/README.md:29-31`）。consul 残留实例清理脚本按当前容器 IP 过滤，可重复执行（`deploy/local/README.md:33-43`）。手工等价注册命令见 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1010-1013`。

文档还给出建项目冒烟（`deploy/local/README.md:63-69`）：

```bash
curl -s -X POST http://localhost:8080/project/api/user/projects/ \
  -H 'Content-Type: application/json' -H 'X-DEVOPS-UID: admin' -H 'X-DEVOPS-TOKEN: devops' \
  -d '{"projectName":"demotest","englishName":"demotest","description":"demotest"}'
```

### 4.6 bkrepo bootstrap（仅在首次部署或清空 `bkrepo-mongo-data` 后）

```bash
cd "$REPO/deploy/local"
./bkrepo-bootstrap.sh
```

来源：`deploy/local/README.md:45-55`。脚本幂等写入平台账号 `bk_ci`（密钥 `devops`）与 bkrepo 管理员 `admin`；`BK_CI_BKREPO_AUTHORIZATION="Platform YmtfY2k6ZGV2b3Bz"` 必须与 `bkenv.properties` 一致，值含空格**必须加引号**，否则 `render_tpl` source 时会被拆开并渲染为空（同处）。本次从卷恢复通常不需要重跑。bkrepo 依赖 mongo 卷与网关别名 `bkrepo.local`（`docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:853-865`；`deploy/local/docker-compose.yml:414-418`）。

### 4.7 插件与图标（按需）

从卷恢复时 9 个默认插件应仍在 store 中，插件包内版本均为 `1.0.0`（`deploy/local/README.md:71-75`）。验证 / 补装 / 列出插件（直连 store 容器 `21918`，因为 op 接口走网关需要登录 Cookie）：

```bash
GW=http://localhost:8080
curl -s -H 'X-DEVOPS-TOKEN: devops' -H 'X-DEVOPS-UID: admin' \
  "$GW/store/api/service/pipeline/atom/codes/checkout/versions/1.0.0"

STORE_PORT=21918
code=checkout
docker cp /tmp/opencode/atoms/$code.zip bkci-store:/tmp/$code.zip
docker exec bkci-store curl -sS -XPOST "http://127.0.0.1:$STORE_PORT/api/op/pipeline/atom/deploy" \
  -H 'X-DEVOPS-UID: admin' -F atomCode=$code -F file=@/tmp/$code.zip
docker exec bkci-store curl -sS -XPOST "http://127.0.0.1:$STORE_PORT/api/op/pipeline/atom/default/atomCodes/$code" \
  -H 'X-DEVOPS-UID: admin'

docker exec bkci-store curl -sS \
  "http://127.0.0.1:21918/api/op/pipeline/atom/?page=1&pageSize=100" \
  -H 'X-DEVOPS-UID: admin'
```

来源：`deploy/local/README.md:83-109`；批量部署 9 个插件的循环见 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:931-945`。插件 zip 需先下载到 `/tmp/opencode/atoms/`（stash 未包含）：8 个官方 zip 的下载 URL 见 `docs/superpowers/plans/2026-11-19-restore-and-verify.md:164-181`；`CodeCCCheckAtom` 官方仓库已删除，公开 fork `huangjiao-heart/CodeCCCheckAtom` 的构建与 `task.json` 补丁说明见 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:927`，运行时兼容性未验证（`deploy/local/README.md:77-81`、`:230`）。

图标修复（容器/卷重建后重跑）：

```bash
cd deploy/local && ./fix-atom-logos.sh
```

来源：`deploy/local/README.md:194-213`。脚本默认从 `/tmp/opencode/atoms` 读 9 个 zip，可用 `ATOMS_DIR` 覆盖（`:205-209`）；它把镜像内置 `support-files/file` 与插件包内 logo 按元数据落位并经网关校验，2026-10-27 结果 9 插件 + 31 内置图标全部 200；残留 `tapdTrigger.png` / `scmGitTrigger.png` 社区包未附带仍 500（`:211-213`）。

### 4.8 前端 dev server + 反代（验证源码改动必须用这条链路）

```bash
cd "$REPO/src/frontend/devops-pipeline"
npm install
npm run dev
```

来源：stash `README.md:144-153`。镜像里的前端来自 release 产物，不消费 `src/frontend`（stash `README.md:146`；`deploy/local/README.md:143`）。另起反代（本机已有未提交脚本，应先提交或拷到新机）：

```bash
node "$REPO/deploy/local/pipeline-dev-proxy.js"
```

规则：`/pipeline/*` → `127.0.0.1:8006`，其余 → `127.0.0.1:8080`，监听 `0.0.0.0:8088`（`docs/superpowers/plans/2026-11-19-restore-and-verify.md:90-144`；stash `README.md:152-155`）。浏览器访问 `http://<host>:8088/console/`；远程访问需防火墙放行 8088（历史命令 `sudo ufw allow 8088/tcp`，见 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1300`）。HMR websocket 固定 `127.0.0.1:8006`，跨机改码后需手动强刷（stash `README.md:142`；部署计划 `:1304`）。node_modules 与 dev 构建产物均被 gitignore（`src/frontend/devops-pipeline/.gitignore:2`、`src/frontend/.gitignore:3`），本机 node_modules 目前存在（现场检查）。

### 4.9 IP/配置变化后的重渲染

```bash
cd "$REPO/deploy/local"
set -a && . ./bkenv.properties && set +a
export INSTALL_PATH="$PWD/rendered"
../../docker-images/core/ci/ci-docker/scripts/render_tpl ../../docker-images/core/ci/ci-docker/support-files/templates/#etc#ci#*.yml
docker compose up -d --force-recreate <变更涉及的服务或 gateway/frontend>
./register-frontend.sh && docker compose restart gateway
```

来源：`docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1015-1019`；`deploy/local/README.md:29-31`、`deploy/local/README.md:17-27`。渲染完成后应检查无残留 `__VAR__` 占位符（部署计划 `:229-235`）。

### 4.10 已知坑（恢复后遇到再处理）

- 网关 `/` 的 302 Location 是 `http://localhost/console/`，请直接访问 `/console/`（`deploy/local/README.md:225-228`）。
- RabbitMQ 卷重建/账号变更后 log 消费者不会自行恢复（`consumers=0`、无构建日志）：`docker restart bkci-log`，再查队列（`:181-192`）。
- ES 起不来：`sudo sysctl -w vm.max_map_count=262144 && docker compose up -d es`（部署计划 `:1021-1025`）。
- 中文数据用 API/curl 写入前 `export LC_ALL=C.UTF-8`（或 `PYTHONUTF8=1`）；判断库里中文是否被写坏只看字节 `hex(...)`，不要看 mysql 客户端显示（`deploy/local/README.md:138`、`:222-223`；部署计划 `:1285-1289`）。
- 后端容器已统一 `LANG/LC_ALL=C.UTF-8`；重新渲染后确认 `common.yml` 中 `bkScs.consumer.concurrency.*: 1` 仍在（`deploy/local/README.md:178-179`、`:215-223`）。

---

## 五、如何使用 bkci-local-stash

### 5.1 内容与用途

| 路径 | 内容 | 用途 / 来源 |
|---|---|---|
| `README.md`、`manifest.txt`、`SHA256SUMS` | 说明、来源清单、192 条校验和 | 迁移入口与完整性校验；stash `README.md:1-12`、`:157-170`；`manifest.txt:1-22` |
| `images/bkci-images.tar.gz`（4.0G）+ `image-list.txt` | 19 个镜像合并包与 tag 列表 | `docker load`；stash `README.md:21-23`、`:68-77`；`manifest.txt:9` |
| `volumes/*.tar.gz`（144M） | mysql/consul/bkrepo-mongo/rabbitmq 四个命名卷 | 用 `docker volume create` + `docker run ... tar xzf` 导入；stash `README.md:24-28`、`:79-88` |
| `config/` | `bkenv.properties`、`bkrepo.env(.fixed)`、`bkrepo-consul-services.json`、`rendered/`、`bkrepo-etc.rendered/` | 被 gitignore 的渲染源与直接挂载产物；stash `README.md:29-35`、`:90-99`；`manifest.txt:11-12` |
| `artifacts/`（989M） | `bkci-slim.tar.gz`(489M)、`ci-docker.tar.gz`(501M) | 重建镜像用的 release 包与含本地补丁的构建上下文；stash `README.md:36-38`、`:101-106` |
| `extras/host-data-bkci-local/`（302M） | 原 `/data/bkci-local`：agent-package、docker、gateway-files、logs | 复制到新机 `/data/bkci-local`；stash `README.md:40`、`:97` |
| `extras/bkrepo-work/`、`extras/extra-jars/` | bkrepo 中间配置、`common-auth-provider-1.9.0.jar` | 前者复制到 `deploy/local/`，后者复制到 `deploy/local/extra-jars/`；stash `README.md:41-42`、`:96-98` |

实际总大小 5.4G（现场 `du -ah`），文档要求新机至少约 20G 可用（镜像解压占用，stash `README.md:49`）；当前旧机 `/` 仍有 248G 可用（现场 `df -h`）。

### 5.2 完整性校验

```bash
cd /home/xsg/aicode/bkci-local-stash
sha256sum -c SHA256SUMS
gzip -t images/bkci-images.tar.gz
for f in volumes/*.tar.gz artifacts/*.tar.gz; do gzip -t "$f"; done
```

来源：stash `README.md:157-164`。**2026-11-20 现场实测**：`sha256sum -c --quiet SHA256SUMS` 退出码 0，192 条全部 OK（SHA256SUMS mtime 仍为 11-19 10:18）。`gzip -t` 本次未逐包运行，建议在新机拷贝后补跑。新增/删除文件后重算：

```bash
find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
```

来源：stash `README.md:166-170`；恢复计划 Task 3 Step 3 给出同一命令（`docs/superpowers/plans/2026-11-19-restore-and-verify.md:194-202`）。

### 5.3 缺失与不完整的部分

- **缺 8 个官方插件 zip**（`checkout`、`run`、`SubPipelineExec`、`uploadArtifact`、`uploadReport`、`AcrossProjectDistribution`、`downloadArtifact`、`PerforceSync`）：`extras/atoms/` 目录不存在，`manifest.txt:19` 与 stash `README.md:45`、`:128` 说明 `/tmp/opencode` 已清空，zip 未入包；恢复计划 Task 3 本应补回（`docs/superpowers/plans/2026-11-19-restore-and-verify.md:158-183`）但未做。
- **缺 CodeCCCheckAtom 可重装包**：官方仓库已删除，只能按 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:927` 从公开 fork 重建；当前插件若随卷仍在 store 中可继续用，但运行时兼容性未验证（`deploy/local/README.md:77-81`、`:230`）。
- **stash 内没有 dev proxy 脚本**：stash `README.md:155` 说旧 `/tmp/opencode/pipeline-dev-proxy.js` 丢失需重建；本机现在已有仓库内未提交版本，必须带上（第六节）。
- 未包含 `deploy/local/bkrepo-logs`（223M，仅日志）、fork SSH key、宿主机 nginx 配置（`manifest.txt:17-20`；stash `README.md:45`）。
- `/tmp/opencode` 并非完全空：还有 11-19 09:31 的 handoff 文件（现场检查），但文档已把它标为过期入口（`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:25`；部署计划 `:5`）。

### 5.4 凭据警告

`config/`、`volumes/` 含明文密码、密钥和业务数据，整个 stash 按私密资料处理，禁止提交 git 或上传公开存储（stash `README.md:9-10`、`:172-176`；`manifest.txt:22`）。现场检查：`config/bkenv.properties`、`config/bkrepo.env`、`config/bkrepo.env.fixed` 均命中密码/密钥类字段；stash 根目录与 `config/` 权限 700、配置文件 600（现场 `stat`），复制时请保留权限。仓库 `.gitignore:73-86` 已排除这些路径，切勿 `git add -f`。

---

## 六、仓库内未提交 / 未跟踪内容的处理

当前 `git status --short --branch`：`## master...origin/master [ahead 90]`、` M deploy/local/README.md`、`?? deploy/local/pipeline-dev-proxy.js`、`?? docs/superpowers/plans/2026-11-19-restore-and-verify.md`（现场）。

| 内容 | 状态 | 建议 |
|---|---|---|
| `deploy/local/README.md:128` | 已修改未提交，内容是 consul IP `172.28.0.77` | 与反代脚本一起提交；这也是恢复计划 Task 2 Step 1 的产物（`docs/superpowers/plans/2026-11-19-restore-and-verify.md:84-86`） |
| `deploy/local/pipeline-dev-proxy.js` | 未跟踪，1434 字节，语法检查通过 | 提交进仓库以替代丢失的 `/tmp` 脚本（计划 `:18`、`:88-144`） |
| `docs/superpowers/plans/2026-11-19-restore-and-verify.md` | 未跟踪，5 个 Task 全未勾选 | 提交前可把本文第二节的真实状态回填进去，或至少追加「迁移交接见 2026-11-20 文档」的注记 |
| `openspec/changes/add-*` 两个活动目录 | 被 `.gitignore:68` 忽略、`git ls-files` 为空 | 不 `git add -f`；验证全通过并 `mv` 到 `archive/`、写 `.openspec.yaml` 后再提交（`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:204`、`:243-262`） |
| `deploy/local/bkenv.properties`、`rendered/`、`bkrepo.env(.fixed)`、`bkrepo-etc.rendered/`、`extra-jars/`、前端 `node_modules` / dev 构建产物 | 全部被 gitignore（`.gitignore:73-86`；`src/frontend/.gitignore:3`；`src/frontend/devops-pipeline/.gitignore:2`） | 靠 stash（或单独加密拷贝）迁移，不进 git |
| stash 本体 | 仓库外 | 单独复制到新机并校验 SHA256（第五节） |

推荐在新机确认无误后执行（**本次交接不执行、不 push origin**；命令来自 `docs/superpowers/plans/2026-11-19-restore-and-verify.md:316-322`）：

```bash
cd "$REPO"
git add deploy/local/README.md deploy/local/pipeline-dev-proxy.js \
  docs/superpowers/plans/2026-11-19-restore-and-verify.md \
  docs/superpowers/plans/2026-11-20-device-migration-handoff.md
git commit -m "docs: 恢复本地环境并记录 openspec 验证结果"
git branch --set-upstream-to=mine/master master
git push mine master
```

远端现实：本机有 `mine`（`ssh://git@ssh.github.com:443/xieshuigeng/bk-ci.git`）与 `origin`（上游 `TencentBlueKing/bk-ci`）两个远端（`git remote -v`）；当前 upstream 仍是 `origin/master`（现场 `git rev-parse`），未设置 `pushRemote`。两份计划均明确要求 `git push mine master`、禁止 `git push origin`（`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:313-316`；`docs/superpowers/plans/2026-11-19-restore-and-verify.md:320-324`）。`master` 超前 `origin/master` 90 个提交属本地/fork 历史，未向上游提 PR（`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:5`、`:63`）。

---

## 七、待办与阻塞项（优先级）

**P0（不带就无法开工）**

1. 带走 5.4G stash + fork SSH key；stash 在仓库外且含明文凭据（`manifest.txt:17-22`；stash `README.md:9-10`）。
2. 带走或提交仓库内 3 项 `M`/`??` 内容，特别是 `pipeline-dev-proxy.js`（现场 `git status`；计划 `:18`、`:88-144`）。
3. 新机把 upstream 改到 `mine/master` 后再 push，避免误推上游（stash `README.md:64`；对账计划 `:313-316`）。
4. 补 8 个插件 zip；CodeCC 需按 fork 重建方案准备（stash `README.md:128`；`docs/superpowers/plans/2026-11-19-restore-and-verify.md:158-192`；部署计划 `:927`）。

**P1（恢复与验证主线）**

5. 从 stash 恢复镜像/卷/配置后按 4.5 启动并跑健康检查；当前主要容器全部退出、端口全关，不能把中午曾启动当作已恢复（现场 `docker ps`、`ss -ltn`、`curl`）。
6. 起 dev server + `:8088` 反代，逐条执行 3.1–3.4、4.1–4.5 浏览器验证并保存截图（计划 `:206-283`；失败项如实留空）。
7. 验证通过后才会做：勾选 openspec、`mv` 到 `archive/` 并写 `.openspec.yaml`、追加部署计划 `### 2026-11-19 恢复与验证` 续节、提交推送 mine（计划 `:281-324`）；如希望改动进入前端镜像，还需重新构建镜像（对账计划 `:171`）。
8. 提交 4 项仓库内改动（含本交接文档），并顺手把恢复计划复选框按真实状态回填（现场 `git status`；计划 `:318-324`）。

**P2（其他尾巴）**

9. `CodeCCCheckAtom` 运行时兼容性未验证；首次用于真实流水线时观察构建日志（`deploy/local/README.md:77-81`、`:139`、`:230`）。
10. Wave B 可选服务、是否向上游提 issue、浏览器全流程走查仍按部署计划遗留项处理（`docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1099-1122`、`:1281`）。
11. bkrepo 图标中 `tapdTrigger.png` / `scmGitTrigger.png` 仍 500，属社区包缺口（`deploy/local/README.md:211-213`）。
12. 文档小冲突：`/tmp/opencode` 实际尚存 handoff 文件（现场 `stat`），但文档写「已清空」（对账计划 `:25`；stash `README.md:45`）；以本文件为准。

---

## 八、信息来源

- `docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md:5-25`、`:41-73`、`:159-190`、`:194-272`、`:276-321`（对账计划与门控）
- `docs/superpowers/plans/2026-11-19-restore-and-verify.md:1-332`（本次核查的 5 个 Task、反代脚本全文、zip 下载与归档门控）
- `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:5`、`:1010-1041`、`:1053-1122`、`:1124-1237`、`:1272-1313`（部署时间线、渲染/插件/重渲染命令、对账续节）
- `deploy/local/README.md:1-61`、`:71-109`、`:110-143`、`:145-232`（部署与运维手册、当前状态、已知限制）
- `deploy/local/docker-compose.yml:3-9`、`:100-194`、`:330-424`（端口、静态 IP、consul/dnsmasq/bkrepo 接线）
- `openspec/changes/add-atom-logo-load-fallback/tasks.md:1-32`、`proposal.md:1-34`
- `openspec/changes/add-blank-pipeline-creation-entry/tasks.md:1-39`、`proposal.md:1-39`
- `/home/xsg/aicode/bkci-local-stash/README.md:1-177`、`manifest.txt:1-22`、`SHA256SUMS`（192 条）、`images/image-list.txt:1-19`
- `/tmp/opencode/handoff-bkci-machine-switch.md:1-45`（旧 handoff，仅作线索）
- 现场只读调查（2026-11-20）：`git status --short --branch`、`git remote -v`、`git log`、`git rev-parse @{upstream}`、`git diff`、`git check-ignore`、`git ls-files`、`ps aux`、`ss -ltn`、`curl`、`docker ps -a`、`docker inspect`、`stat`、`du -ah`、`df -h`、`node --check`、`git diff --check`、`sha256sum -c --quiet SHA256SUMS`（退出码 0）
