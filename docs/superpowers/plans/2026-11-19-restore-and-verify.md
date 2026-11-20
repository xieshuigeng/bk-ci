# 本地环境恢复、openspec 验证与小尾巴收尾实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 恢复本机 bk-ci Docker 部署并启动前端 dev 调试链路，完成两个 openspec 变更的逐条验证，修掉已识别的三个小尾巴（README 旧 IP、反代脚本丢失、插件 zip 丢失）。

**Architecture:** 当前机器已有完整数据卷与 gitignore 配置，走“原地重启”快路径而不是全量导入迁移包；前端源码改动只通过 dev server + 本地反代验证，不伪造 release 镜像已包含改动；验证结果写入 openspec `tasks.md`，全部通过后才允许归档。

**Tech Stack:** Docker 24 / Compose v2、Node 22 / npm、Chrome 浏览器手工验证、Markdown 记录、git（仅推 `mine/master`）。

> **执行状态（2026-11-20 迁移交接核实）:** 本计划下方复选框为原始起草状态，未随实际执行更新。实际仅 Task 2 的本机文件改动落地（README 旧 IP 改 `172.28.0.77`、新增 `pipeline-dev-proxy.js`，提交前均为未提交状态），Task 1/3/4/5 未执行。真实状态、部署步骤与迁移包用法见 `docs/superpowers/plans/2026-11-20-device-migration-handoff.md`。

---

## 文件结构

| 文件 | 责任 | 动作 |
|---|---|---|
| `deploy/local/README.md` | 运维手册 | `:128` 旧 consul IP 改 `172.28.0.77` |
| `deploy/local/pipeline-dev-proxy.js` | 前端调试反代（持久化，替代丢失的 `/tmp/opencode/pipeline-dev-proxy.js`） | 新建并提交 |
| `/home/xsg/aicode/bkci-local-stash/extras/atoms/` | 插件 zip 私密存放（仓库外） | 补回 8 个官方插件 zip；CodeCC 尝试从已安装 store 中提取 |
| `/home/xsg/aicode/bkci-local-stash/README.md` | 迁移包说明 | 更新插件 zip 状态 |
| `/home/xsg/aicode/bkci-local-stash/manifest.txt` | 迁移包清单 | 更新插件 zip 状态 |
| `/home/xsg/aicode/bkci-local-stash/SHA256SUMS` | 迁移包校验 | 新增 zip 后重算 |
| `openspec/changes/add-atom-logo-load-fallback/tasks.md` | 图标回退验证清单 | 写入 3.1–3.4 验证结果（本机记录，不提交） |
| `openspec/changes/add-blank-pipeline-creation-entry/tasks.md` | 空白创建验证清单 | 写入 4.1–4.5 验证结果（本机记录，不提交） |
| `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md` | 部署主计划 | 追加验证结果续节并提交 |
| `docs/superpowers/plans/2026-11-19-restore-and-verify.md` | 本计划 | 勾选执行状态并提交 |

---

## Task 1: 原地恢复 Docker 部署并做健康检查

- [ ] **Step 1: 前置检查**

```bash
cd /home/xsg/aicode/bk-ci
docker version --format '{{.Server.Version}}'
docker compose -f deploy/local/docker-compose.yml config --quiet
for v in bkci_mysql-data bkci_consul-data bkci_bkrepo-mongo-data bkci_rabbitmq-data; do docker volume inspect "$v" >/dev/null || exit 1; done
ss -ltn | grep -E ':8080|:8500|:5000|:5672' || echo PORTS_IDLE
```

Expected: Docker 版本输出；`config --quiet` 无输出；4 个卷都存在；端口要么空闲要么仅被 bkci 占用。

- [ ] **Step 2: 启动 compose（不启用 `engine` profile）**

```bash
docker compose -f deploy/local/docker-compose.yml up -d
sleep 30
docker compose -f deploy/local/docker-compose.yml ps
```

Expected: 无 `engine` 容器；`bkci-process`、`bkci-mysql`、`bkci-consul`、`bkci-gateway`、`bkci-frontend` 等处于 Up；`bkci-bkrepo-repository` 已 Up 时保持 Up。

- [ ] **Step 3: 执行注册与清理后置动作**

```bash
cd /home/xsg/aicode/bk-ci/deploy/local
./register-frontend.sh
./consul-cleanup.sh --dry-run
./consul-cleanup.sh
docker compose restart gateway
```

Expected: 脚本正常退出；consul 中 `frontend` 服务重新注册；gateway 重启后无报错。

- [ ] **Step 4: 健康验证**

```bash
curl -s -o /dev/null -w 'console:%{http_code}\n' http://localhost:8080/console/
curl -s http://localhost:8500/v1/agent/services | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d), 'services registered')"
docker compose -f /home/xsg/aicode/bk-ci/deploy/local/docker-compose.yml ps --format '{{.Name}}\t{{.Status}}' | grep -v 'Up' || echo ALL_UP
```

Expected: `console:200` 或 `console:302`；注册服务数大于 0；最后输出 `ALL_UP`（`engine` 不在 compose 默认 profile 中，不应出现）。

---

## Task 2: 修小尾巴 A — README 旧 IP 与持久化反代脚本

**Files:**
- Modify: `deploy/local/README.md:128`
- Create: `deploy/local/pipeline-dev-proxy.js`

- [ ] **Step 1: 修正 README 中的旧 consul IP**

把 `deploy/local/README.md:128` 的 `172.28.0.10` 改为 `172.28.0.77`。

- [ ] **Step 2: 新建持久化的 dev 反代脚本**

新建 `deploy/local/pipeline-dev-proxy.js`，内容如下：

```js
const http = require('http');
const net = require('net');

const PORT = 8088;
const TARGETS = {
  pipeline: { host: '127.0.0.1', port: 8006 },
  default: { host: '127.0.0.1', port: 8080 },
};

function pick(url) {
  return url && url.startsWith('/pipeline/') ? TARGETS.pipeline : TARGETS.default;
}

const server = http.createServer((req, res) => {
  const target = pick(req.url);
  const proxy = http.request({
    host: target.host,
    port: target.port,
    path: req.url,
    method: req.method,
    headers: { ...req.headers, host: `${target.host}:${target.port}` },
  }, (upstream) => {
    res.writeHead(upstream.statusCode || 502, upstream.headers);
    upstream.pipe(res);
  });
  proxy.on('error', () => {
    res.writeHead(502);
    res.end('bad gateway');
  });
  req.pipe(proxy);
});

server.on('upgrade', (req, socket, head) => {
  const target = pick(req.url);
  const upstream = net.connect(target.port, target.host, () => {
    upstream.write(
      `${req.method} ${req.url} HTTP/${req.httpVersion}\r\n` +
      Object.entries(req.headers).map(([k, v]) => `${k}: ${v}`).join('\r\n') +
      '\r\n\r\n'
    );
    if (head.length) upstream.write(head);
    socket.pipe(upstream);
    upstream.pipe(socket);
  });
  upstream.on('error', () => socket.destroy());
  socket.on('error', () => upstream.destroy());
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`pipeline dev proxy listening on :${PORT}`);
});
```

- [ ] **Step 3: 校验脚本语法**

```bash
node --check deploy/local/pipeline-dev-proxy.js
grep -n '172.28.0.77' deploy/local/README.md
git diff --check -- deploy/local/README.md deploy/local/pipeline-dev-proxy.js
```

Expected: 无语法错误；README 命中 1 行；diff check 无输出。

---

## Task 3: 修小尾巴 B — 补回插件 zip 到迁移包

**Files:**
- Create（仓库外）: `/home/xsg/aicode/bkci-local-stash/extras/atoms/*.zip`
- Modify（仓库外）: stash `README.md`、`manifest.txt`、`SHA256SUMS`

- [ ] **Step 1: 下载 8 个官方插件 zip**

```bash
STASH=/home/xsg/aicode/bkci-local-stash
mkdir -p "$STASH/extras/atoms"
cd "$STASH/extras/atoms"
BASE=https://ghfast.top/https://github.com/TencentBlueKing
curl -sSL -o checkout.zip     "$BASE/ci-checkout/releases/download/v2.0.13/checkout_en.zip"
curl -sSL -o run.zip          "$BASE/ci-run/releases/download/v1.0.5/run-v1.0.5.zip"
curl -sSL -o SubPipelineExec.zip "$BASE/ci-SubPipelineExec/releases/download/v1.0.6/ci-SubPipelineExec_en.zip"
curl -sSL -o uploadArtifact.zip  "$BASE/ci-uploadArtifact/releases/download/v2.0.1/uploadArtifact_en.zip"
curl -sSL -o uploadReport.zip    "$BASE/ci-uploadReport/releases/download/v1.0.1/uploadReport_en.zip"
curl -sSL -o AcrossProjectDistribution.zip "$BASE/ci-AcrossProjectDistribution/releases/download/v1.1.1/AcrossProjectDistribution_en.zip"
curl -sSL -o downloadArtifact.zip "$BASE/ci-downloadArtifact/releases/download/v1.0.2/downloadArtifact_en.zip"
curl -sSL -o PerforceSync.zip "$BASE/ci-plugin-perforce-sync/releases/download/v1.0.13/PerforceSync_en.zip"
ls -lh *.zip
file *.zip
```

Expected: 8 个 zip 每个 ≥10KB；`file` 输出均为 `Zip archive data`。

- [ ] **Step 2: 尝试从已安装 store 中提取 CodeCC zip**

```bash
docker exec bkci-store sh -c 'find / -type f -iname "*CodeCC*.zip" 2>/dev/null | head -5'
docker exec bkci-artifactory sh -c 'find /data -type f -iname "*CodeCC*.zip" 2>/dev/null | head -5'
```

Expected: 若找到文件，用 `docker cp` 复制到 `$STASH/extras/atoms/CodeCCCheckAtom.zip` 并 `file` 校验；若都为空，保留缺失状态并在 stash 文档中写明“官方仓库已删、重建命令未保留，需按部署计划 Task 12.3 说明从 fork 重新构建”。

- [ ] **Step 3: 更新迁移包文档与校验和**

```bash
cd /home/xsg/aicode/bkci-local-stash
find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
sha256sum -c SHA256SUMS
```

Expected: 全部 OK；stash 文档说明与实际 zip 数量一致。

---

## Task 4: 启动 dev server + 反代，并执行可自动化的验证

**Files:** 无（运行时进程与日志）

- [ ] **Step 1: 启动前端 dev server**

```bash
mkdir -p /tmp/opencode
cd /home/xsg/aicode/bk-ci/src/frontend/devops-pipeline
nohup npm run dev > /tmp/opencode/pipeline-dev.log 2>&1 &
echo $! > /tmp/opencode/pipeline-dev.pid
for i in $(seq 1 90); do curl -sf -o /dev/null http://127.0.0.1:8006/ && break; sleep 2; done
curl -s -o /dev/null -w 'devserver:%{http_code}\n' http://127.0.0.1:8006/
```

Expected: `devserver:200`；日志中 webpack 编译成功。

- [ ] **Step 2: 启动持久化反代**

```bash
cd /home/xsg/aicode/bk-ci
nohup node deploy/local/pipeline-dev-proxy.js > /tmp/opencode/pipeline-proxy.log 2>&1 &
echo $! > /tmp/opencode/pipeline-proxy.pid
sleep 2
curl -s -o /dev/null -w 'proxy-console:%{http_code}\n' http://127.0.0.1:8088/console/
curl -s -o /dev/null -w 'proxy-pipeline:%{http_code}\n' http://127.0.0.1:8088/pipeline/
```

Expected: 两个状态码均非 502；`proxy-console` 为 200/302。

- [ ] **Step 3: 静态验证 dev 产物包含源码改动**

```bash
grep -R -l 'AtomLogo' /home/xsg/aicode/bk-ci/src/frontend/frontend/pipeline/ | head -5
grep -R -l 'hasUsableTemplate' /home/xsg/aicode/bk-ci/src/frontend/frontend/pipeline/ | head -5
```

Expected: 两条命令均至少命中 1 个文件，证明 dev server 产物来自已改源码。

- [ ] **Step 4: API 验证 4.4（模板不存在空态的数据前提）**

```bash
curl -s -H 'X-DEVOPS-UID: admin' \
  http://localhost:8088/process/api/user/pipeline/template/v2/demo/allTemplates
```

Expected: 返回体含 `2101034` 或空模板列表；若返回登录/权限错误，记录为“环境鉴权未打通，需浏览器登录后手工验证 4.4”。

---

## Task 5: 记录验证结果、归档门控与提交

**Files:**
- Modify（本机）: `openspec/changes/add-atom-logo-load-fallback/tasks.md`
- Modify（本机）: `openspec/changes/add-blank-pipeline-creation-entry/tasks.md`
- Modify: `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md`
- Modify: `docs/superpowers/plans/2026-11-19-restore-and-verify.md`
- Commit: `deploy/local/README.md`、`deploy/local/pipeline-dev-proxy.js` 与上述两个计划文件

- [ ] **Step 1: 执行浏览器人工验证清单**

浏览器访问 `http://127.0.0.1:8088/console/`，逐条执行并把实际观察写入对应 `tasks.md` 的“验证状态（2026-11-19）”小节：

- 3.1：`logoUrl` 返回 200 的原子，DOM 仍为 `<img>`，尺寸/类名与改动前一致。
- 3.2：`codeTapdWebHookTrigger`（`tapdTrigger.png`）负载例，显示 sprite 而非裂图；Network 中同一 URL 只请求一次。
- 3.3：构造 sprite 不存在的 `name`，落到 `#bk-pipeline-order`。
- 3.4：`demo` 项目画布、执行历史、原子选择器、插件管理页图标均可见。
- 4.1：模板商店为空时空白创建引导出现；创建、进编排页、保存并发布成功，记录 pipelineId。
- 4.2：安装任一模板后，模板选择/自由约束/复制模板配置与改动前一致。
- 4.3：无 CREATE 权限用户入口禁用并有权限提示。
- 4.4：`allTemplates` 返回 `2101034` 时无错误弹窗，页面空态渲染。
- 4.5：跨工程复制/导入流水线入口回归正常。

截图统一保存到 `/home/xsg/aicode/bkci-local-stash/extras/verification-screenshots/`，并在 `tasks.md` 写入实际文件路径。

- [ ] **Step 2: 按结果更新 openspec 任务状态**

只把实际通过的条目改为 `[x]`；未通过或因环境不具备未验证的条目保持 `[ ]` 并写明具体失败现象。不得批量勾选。

- [ ] **Step 3: 归档门控**

仅当 3.1–3.4 与 4.1–4.5 全部为 `[x]` 时执行：

```bash
cd /home/xsg/aicode/bk-ci
mv openspec/changes/add-atom-logo-load-fallback openspec/changes/archive/2026-11-19-add-atom-logo-load-fallback
mv openspec/changes/add-blank-pipeline-creation-entry openspec/changes/archive/2026-11-19-add-blank-pipeline-creation-entry
```

随后在两个归档目录各写 `.openspec.yaml`：

```yaml
schema: spec-driven
created: 2026-10-27
```

再执行：

```bash
git add openspec/changes/archive/2026-11-19-add-atom-logo-load-fallback openspec/changes/archive/2026-11-19-add-blank-pipeline-creation-entry
```

未全部通过时不得执行本步；归档保持未创建。

- [ ] **Step 4: 追加结果续节并提交**

在 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md` 文末追加 `### 2026-11-19 恢复与验证` 小节，写入服务恢复状态、dev server/反代可用性、9 项验证逐条结果、仍未通过项与原因、归档是否执行。

然后执行：

```bash
cd /home/xsg/aicode/bk-ci
git add deploy/local/README.md deploy/local/pipeline-dev-proxy.js docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md docs/superpowers/plans/2026-11-19-restore-and-verify.md
git commit -m "docs: 恢复本地环境并记录 openspec 验证结果"
git push mine master
git log --oneline -1 mine/master
```

Expected: 提交成功并推送 `mine/master`；不得执行 `git push origin`。

---

## 自查记录（writing-plans self-review）

1. **覆盖检查**：恢复（Task 1）、README 旧 IP（Task 2 Step 1）、反代脚本丢失（Task 2 Step 2）、插件 zip 丢失（Task 3）、验证（Task 4/5）、归档门控（Task 5 Step 3）、提交（Task 5 Step 4）均有对应任务。
2. **占位符扫描**：所有命令、路径、文件内容均给出；人工验证结果必须由实际观察填写，已给出逐条判定标准和记录位置，未使用空泛占位。
3. **类型/名称一致性**：脚本名 `pipeline-dev-proxy.js`、端口 8006/8080/8088、卷名、openspec 目录名与前文文档一致；远端名统一为 `mine`。
