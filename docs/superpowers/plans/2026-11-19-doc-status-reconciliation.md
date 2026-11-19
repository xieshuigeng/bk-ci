# 文档状态对账与收尾实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 4 类版本化文档与事实不一致之处，把 openspec 的验证/归档路径写实；不改产品代码、不迁移环境、**不向 TencentBlueKing/bk-ci 提任何 PR**。

**Architecture:** 改动仅限 `docs/superpowers/`、`deploy/local/README.md`、`openspec/changes/`。历史计划正文与勾选保留原貌，用"当前状态注记 + 文末续节"承接；未实际验证的 openspec 项**不勾完成**，只记录验证前置条件与命令；验证通过后才执行归档（git mv + `.openspec.yaml`）。

**Tech Stack:** Markdown、git、grep；验证阶段才需要浏览器、dev server（`:8006`）、反代（`:8088`）与本地 Docker 部署。

> **计划记录位置**：本文件 `docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md`。
> **执行状态记录**：本文件复选框；最终结果另在 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md` 追加 `### 2026-11-19 文档状态对账` 续节。
> **执行状态（2026-11-19）**：用户确认后已按计划执行完毕；本文件随 Task 5 Step 3 的提交入库，提交 hash 见 `git log -1`。归档门控（Task 4 Step 3）因验证项未勾选而保留未完成状态。

---

## 前置说明（执行者必读）

1. 本轮只做文档对账，不做研发改动、不重装环境、不推送上游。唯一远端目标是个人 fork `mine/master`。
2. 事实来源以 git 历史与既有续节为准，不以计划正文复选框为准：
   - `8ff8795` 前端返回箭头；`c882113` LANG 修正；`db1b676` 文档提交；`2255681` AtomLogo + 空白创建；`7ead01d7130` consul IP 修正。
   - 返回箭头浏览器复验结果在 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1296-1300`。
   - UI 走查三项根因在 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1196-1279`。
3. 迁移包 `/home/xsg/aicode/bkci-local-stash/` 在仓库外，含明文凭据；本计划不引用其具体值，也不提交它。
4. `/tmp/opencode/` 已清空；任何指向该目录的"继续前先读"提示都必须改写。

## 文件结构

| 文件 | 责任 | 动作 |
|---|---|---|
| `docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md` | 本计划 | 创建（当前步骤） |
| `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md` | 部署主时间线 | 改状态注记、13.5；执行完成后追加对账续节 |
| `docs/superpowers/plans/2026-10-29-pipeline-breadcrumb-back-arrow.md` | 返回箭头计划 | Task 2–4 回填真实结果，消除占位符 |
| `deploy/local/README.md` | 运维手册 | 当前状态补"已实现待验证"；已知限制改为反映代码现状 |
| `openspec/changes/add-atom-logo-load-fallback/tasks.md` | 图标回退验证清单 | 追加验证状态与前置条件，不勾完成 |
| `openspec/changes/add-blank-pipeline-creation-entry/tasks.md` | 空白创建验证清单 | 追加验证状态与前置条件，不勾完成 |
| `openspec/changes/archive/2026-11-19-*` | 归档目录 | **门控步骤**：仅验证全通过后才创建 |

---

## Task 1: 部署计划状态注记与 Task 13.5 回填

**背景分析**：文件顶部 `:5` 写"Task 9 起未执行、全程未 commit、先读 /tmp handoff"，与 `:1051+` 的续节和 git 历史直接矛盾；`/tmp` 文件已不存在。正文勾选是历史快照，不应批量改写；应改为"正文保留历史 + 续节为准"的指针。`:1028` 的 13.5 仍未勾选，但用户已确认并且代码已推送 fork。

**Files:**
- Modify: `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:5`、`:1028`

- [x] **Step 1: 替换顶部执行进度注记**

把第 5 行整行替换为：

```markdown
> **执行状态（2026-11-19 对账）:** 本文上半部保留 2026-10-20 原始逐步计划及其历史勾选；**实际完成情况以文末续节为准**：`附录：实施总结`（`:1051`）、`2026-10-23 续`（`:1122`）、`2026-10-26 续`（`:1179`）、`UI 走查问题清单`（`:1196`）、`2026-10-27 续`（`:1270`）、`续二`（`:1281`）、`2026-10-29 返回箭头验收`（`:1296`）。精简状态见 `deploy/local/README.md:134`。旧 handoff `/tmp/opencode/handoff-bkci-docker-deploy-2026-10-20.md` 已随临时目录清空，不再作为入口；迁移包位置与用法见仓库外的 `/home/xsg/aicode/bkci-local-stash/README.md`。
```

- [x] **Step 2: 回填 Task 13.5**

把 `:1028` 的原 checkbox 行替换为：

```markdown
- [x] **Step 13.5: （询问用户后执行）提交 deploy/local 到 fork**

结果（2026-11-19）：用户确认后已推送个人 fork `mine/master`，未向 TencentBlueKing/bk-ci 提 PR。相关提交：`ba8eb2e`（部署配置）、`a485e93`（UI 根因）、`8ff8795`/`c882113`/`db1b676`（前端与文档）、`2255681`（两个 openspec 实现）、`7ead01d7130`（consul IP 修正）。**不得**提交 `rendered/`、`bkci-slim.tar.gz`、解包目录或任何渲染产物；该约束不变。
```

- [x] **Step 3: 验证本任务**

Run:
```bash
grep -n '2026-11-19 对账\|Step 13.5' docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md
git diff --check -- docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md
```
Expected: 两处命中；`git diff --check` 无输出（无空白错误）。

---

## Task 2: 返回箭头计划 Task 2–4 回填

**背景分析**：Task 1 已勾选且无误；Task 2 的两步实际都已完成（dev server 可跑、浏览器两轮复验），Task 3 的模板尖括号仍为空且要求"重复追加"到部署计划，但内容已在部署计划 `:1296-1300`，应改为"确认已有、不重复"。Task 4 三个提交已存在，第四个"工作区干净"当时成立、现在也成立。

**Files:**
- Modify: `docs/superpowers/plans/2026-10-29-pipeline-breadcrumb-back-arrow.md:82`、`:91`、`:105-120`、`:126-151`

- [x] **Step 1: 回填 Task 2 两步**

把 `:82` 与 `:91` 两行分别替换为：

```markdown
- [x] **Step 1: 启动 dev server**

结果（2026-10-29）：本机 `src/frontend/devops-pipeline` 内 `npm run dev` 成功（webpack 5.76.3，全量编译约 56s，无需 pnpm）；反代 `:8088`（`/pipeline/*`→`:8006`，其余→`:8080`）后浏览器可达。详见 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1298`。
```

```markdown
- [x] **Step 2: 浏览器手工验收（人工步骤，由用户执行）**

结果（2026-10-29，两轮）：轮 1 箭头出现、编排/执行记录/预览页无箭头有 logo ✓，但箭头目标错误（流水线列表），用户指正应为构建列表；新增 `backRoute` prop 后轮 2 复验通过：箭头落 `.../<pipelineId>/history/history`，面包屑「流水线」项仍回列表，其余页维持 logo 无箭头。详见 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1300`。
```

- [x] **Step 2: 把 Task 3 从"追加模板"改为"确认已记录"**

把 `:105-120` 整个 `## Task 3` 段落替换为：

````markdown
## Task 3: 验证状态记录

**Files:**
- Modify: 无（状态已存在于 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md:1296-1300`，不重复追加）

- [x] **Step 1: 确认部署计划已含验证小节**

Run:
```bash
grep -n '2026-10-29 返回箭头修复：浏览器验证已补做并通过' docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md
```
Expected: 命中 1 行；小节内含 eslint exit=0、dev server 可用、轮 1/轮 2 结果与设计修订。无需再写占位模板。
````

- [x] **Step 3: 回填 Task 4 四个提交步骤**

把 `:126`、`:133`、`:140`、`:147` 四行分别替换为：

```markdown
- [x] **Step 1: 提交前端修复**

结果：提交 `8ff8795`（`showBack` + `backRoute` 修复，含用户指正后的修订）。
```

```markdown
- [x] **Step 2: 提交 LANG 修正及其部署文档**

结果：提交 `c882113`（compose 的 `LANG/LC_ALL=C.UTF-8` 与 README 排障记录）。
```

```markdown
- [x] **Step 3: 提交 superpowers 文档（spec + 两份 plan）**

结果：提交 `db1b676`（返回箭头 spec/plan + 部署计划 10-27/10-29 记录）。
```

```markdown
- [x] **Step 4: 确认工作区干净**

结果：提交后工作区干净；2026-11-19 对账时再次确认（本轮文档改动提交前除外）。
```

- [x] **Step 4: 验证本任务**

Run:
```bash
grep -n '<dev server 结果\|<逐条结果' docs/superpowers/plans/2026-10-29-pipeline-breadcrumb-back-arrow.md || echo NO_PLACEHOLDER
grep -n -- '- \[ \]' docs/superpowers/plans/2026-10-29-pipeline-breadcrumb-back-arrow.md || echo NO_UNCHECKED_TASK
git diff --check -- docs/superpowers/plans/2026-10-29-pipeline-breadcrumb-back-arrow.md
```
Expected: `NO_PLACEHOLDER`；`NO_UNCHECKED_TASK`（第 3 行的语法说明含 `- [ ]` 字样但不是任务项，若命中该行属正常）；`git diff --check` 无输出。

---

## Task 3: 运维手册已知限制与当前状态对齐

**背景分析**：`README.md:230-232` 说 UI 只能导入、空白新建要走 API——这是实现前的结论。代码已实现（提交 `2255681`），但当前前端镜像来自 release 产物、不含该改动，且 openspec 验证项未做，因此不能写成"已可用"。同样，图标回退单元已实现但未进镜像。方案是保留"当前镜像下"的限制说明，同时新增"代码已实现、待验证/待重构建"的状态说明。

**Files:**
- Modify: `deploy/local/README.md:134-142`、`:224-232`

- [x] **Step 1: 在「当前状态（精简）」追加一条**

在 `:142` 之后追加：

```markdown
- 已实现但**未验证/未进镜像**（提交 `2255681`）：原子图标加载失败回退单元 `AtomLogo`、无可用模板时的空白创建入口。当前前端镜像来自 release 产物，不包含这两项源码改动；openspec 验证项仍未勾选（见 `openspec/changes/add-atom-logo-load-fallback/tasks.md`、`openspec/changes/add-blank-pipeline-creation-entry/tasks.md`）。需在新机用 dev server + `:8088` 反代验证通过、并重新构建前端镜像后才算落地。
```

- [x] **Step 2: 替换「已知限制」中过时的空白创建条目**

把 `:230-232` 三条替换为：

```markdown
- 模板商店为空（`GET /store/api/user/market/template/list` → `count:0`；项目侧 `GET /process/api/user/pipeline/template/v2/<project>/allTemplates` → `2101034 模板不存在`）。**当前镜像**下新建流水线仍只能「导入」或走 API：`POST /process/api/user/pipelines/{projectId}`（body 为流水线 `Model`）。代码层面已新增空白创建入口（`openspec/changes/add-blank-pipeline-creation-entry/`，提交 `2255681`），但尚未随 release 镜像重建、也未完成浏览器验证，故不能按"已可用"对待。
- 原子图标加载失败（社区包缺 `tapdTrigger.png`/`scmGitTrigger.png` 等）仍表现为无图标；`fix-atom-logos.sh` 修复的是 artifactory 静态文件。前端回退单元 `AtomLogo`（`openspec/changes/add-atom-logo-load-fallback/`，提交 `2255681`）同样未进镜像、未验证。
```

- [x] **Step 3: 验证本任务**

Run:
```bash
grep -n '已实现但\*\*未验证\|当前镜像.*只能' deploy/local/README.md
git diff --check -- deploy/local/README.md
```
Expected: 各命中 1 行；`git diff --check` 无输出。

---

## Task 4: openspec 验证待办写实与归档门控

**背景分析**：两个提案的实现任务已 `[x]` 且代码已提交，但验证小节为空且目录仍在 `openspec/changes/` 主动区。直接勾完成或立即归档会虚报。方案：先在各自 `tasks.md` 追加"验证状态（2026-11-19）"，写明**未勾选原因、前置条件、逐条可执行验证命令与记录位置**；只有验证全部通过后，才用 `mv` 归档（活动目录未被 git 跟踪）并补 `.openspec.yaml`。归档门控是本任务的一部分，但本轮不执行。

**Files:**
- Modify（本机记录，不进本轮提交）: `openspec/changes/add-atom-logo-load-fallback/tasks.md`（文件末尾追加）
- Modify（本机记录，不进本轮提交）: `openspec/changes/add-blank-pipeline-creation-entry/tasks.md`（文件末尾追加）
- Create（门控步骤，验证通过后）: `openspec/changes/archive/2026-11-19-add-atom-logo-load-fallback/`、`.openspec.yaml`
- Create（门控步骤，验证通过后）: `openspec/changes/archive/2026-11-19-add-blank-pipeline-creation-entry/`、`.openspec.yaml`

> **执行中发现并修正**：`.gitignore:68` 忽略 `openspec/changes/*`，两个活动变更目录及其 `tasks.md` 原本未被 git 跟踪（`.gitignore:69` 仅放行 `archive/`）。因此本轮对这两个文件的修改是本机记录，**不执行 `git add -f`**；待验证通过后用 `mv` 移入 `archive/` 再 `git add`，届时随归档提交纳入版本控制。

- [x] **Step 1: 追加图标回退验证状态**

在 `openspec/changes/add-atom-logo-load-fallback/tasks.md` 末尾追加：

```markdown
## 验证状态（2026-11-19）

3.1–3.4 **未勾选**：本轮只做文档对账；且前端镜像来自 release 产物、不含 `AtomLogo`，当前部署未重建镜像。验证前置：新机按 `/home/xsg/aicode/bkci-local-stash/README.md` 恢复后，在 `src/frontend/devops-pipeline` 执行 `npm run dev`（`:8006`）+ 反代 `:8088`，浏览器访问 `http://<host>:8088/console/`。

逐条验证口径：
- 3.1 让 `logoUrl` 返回 200（内置图标经网关可达的原子），对比改动前后截图/DOM：仍为 `<img>`，尺寸与类名一致。
- 3.2 用本地环境确实 500 的 `codeTapdWebHookTrigger`（`tapdTrigger.png`）作负例：应显示 sprite 图标而非裂图；浏览器 Network 面板确认同一 URL 只请求一次（模块级 `Set` 缓存生效）。
- 3.3 构造 sprite 中不存在的 `name`，应落到 `#bk-pipeline-order` 兜底图标。
- 3.4 本地部署 `demo` 项目下查看画布、执行历史、原子选择器、插件管理页，确认图标均可见；记录截图路径。

结果写入本节并同步到 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md` 新增的 `### 2026-11-19 openspec 验证` 续节。四项全通过后才允许勾选并归档。
```

- [x] **Step 2: 追加空白创建验证状态**

在 `openspec/changes/add-blank-pipeline-creation-entry/tasks.md` 末尾追加：

```markdown
## 验证状态（2026-11-19）

4.1–4.5 **未勾选**：本轮只做文档对账；当前前端镜像不含该改动，且本地模板商店为空、无第二个有权限用户。验证前置：同 `add-atom-logo-load-fallback` 的 dev server + `:8088` 反代；准备一个已安装模板项目与一个无 CREATE 权限用户，或逐条写明"因环境不具备未验证"并保留未勾选。

逐条验证口径：
- 4.1 项目模板与商店皆空 → 新建页出现空白创建引导 → 创建、进入编排页、保存并发布，记录 pipelineId 与构建触发结果。
- 4.2 先通过 API 安装任一模板 → 原"选模板 + 自由/约束 + 复制模板配置"流程与改动前一致。
- 4.3 无 CREATE 权限用户：入口禁用并出现既有权限提示。
- 4.4 `allTemplates` 返回 `2101034` 时无错误弹窗，页面按空态渲染（本地当前即为该状态，可直接验）。
- 4.5 交叉工程复制/导入流水线入口回归（手工步骤记录）。

结果写入本节并同步到 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md` 新增的 `### 2026-11-19 openspec 验证` 续节。五项全通过后才允许勾选并归档。
```

- [ ] **Step 3: 归档门控（仅在上两步全通过且勾选后执行）**

> 本轮未执行：验证项 3.1–3.4 / 4.1–4.5 仍未勾选，新机恢复前不得归档。此步保留未完成状态，待后续验证通过后单独回填。

Run（在对应验证通过后）:
```bash
cd /home/xsg/aicode/bk-ci
mv openspec/changes/add-atom-logo-load-fallback openspec/changes/archive/2026-11-19-add-atom-logo-load-fallback
mv openspec/changes/add-blank-pipeline-creation-entry openspec/changes/archive/2026-11-19-add-blank-pipeline-creation-entry
```
随后在两个归档目录各写 `.openspec.yaml`，内容为：

```yaml
schema: spec-driven
created: 2026-10-27
```

再执行 `git add openspec/changes/archive/2026-11-19-add-atom-logo-load-fallback openspec/changes/archive/2026-11-19-add-blank-pipeline-creation-entry`。

Expected: `git status --short` 显示 `A  openspec/changes/archive/2026-11-19-...`（活动目录原本未跟踪，故是新增而非重命名）；`.gitignore:69` 放行 `openspec/changes/archive/`。未通过验证时**不得执行本步**。

- [x] **Step 4: 验证本任务（本轮）**

Run:
```bash
grep -n '验证状态（2026-11-19）\|未勾选' openspec/changes/add-atom-logo-load-fallback/tasks.md openspec/changes/add-blank-pipeline-creation-entry/tasks.md
git diff --check -- openspec/changes/add-atom-logo-load-fallback/tasks.md openspec/changes/add-blank-pipeline-creation-entry/tasks.md
ls -d openspec/changes/archive/2026-11-19-* 2>/dev/null || echo NOT_ARCHIVED_YET
```
Expected: 两个文件各命中验证小节；`git diff --check` 无输出；`NOT_ARCHIVED_YET`（本轮不应归档）。

---

## Task 5: 全量验证、交付记录与提交（确认后执行）

**Files:**
- Modify: `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md`（追加对账续节）
- Commit: 上述全部文档文件

- [x] **Step 1: 追加对账续节**

在部署计划文末追加：

```markdown
### 2026-11-19 文档状态对账

- 顶部进度注记改为"正文保留历史、续节为准"；旧 `/tmp` handoff 入口已移除。
- Task 13.5 标记完成：已推送个人 fork `mine/master`（最终提交 `7ead01d7130`），未向上游提 PR。
- `2026-10-29` 面包屑计划 Task 2–4 回填真实结果，占位模板删除。
- `deploy/local/README.md` 区分"当前镜像限制"与"代码已实现待验证"。
- 两个 openspec 追加验证前置与逐条口径；**均未勾选、未归档**，待新机恢复后验证通过再归档。
- 本轮计划与结果记录：`docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md`。
```

- [x] **Step 2: 全量静态验证**

Run:
```bash
git diff --check
grep -RIn 'TBD\|TODO\|<dev server 结果\|<逐条结果' docs/superpowers/plans/2026-10-29-pipeline-breadcrumb-back-arrow.md deploy/local/README.md openspec/changes/add-atom-logo-load-fallback/tasks.md openspec/changes/add-blank-pipeline-creation-entry/tasks.md || echo NO_PLACEHOLDER
git status --short
```
Expected: `git diff --check` 无输出；`NO_PLACEHOLDER`；`git status --short` 仅列出本计划版本的 4 个文件（不含被 `.gitignore:68` 忽略的活动 openspec 记录、迁移包/密钥/渲染产物）。

- [x] **Step 3: 提交到 fork**

Run:
```bash
git add docs/superpowers/plans/2026-11-19-doc-status-reconciliation.md docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md docs/superpowers/plans/2026-10-29-pipeline-breadcrumb-back-arrow.md deploy/local/README.md
git commit -m "docs: 对账部署/前端计划状态，openspec 验证待办写实（不提上游 PR）"
git push mine master
git log --oneline -1 mine/master
```
Expected: 提交成功；`mine/master` 指向新提交；工作区干净（被 `.gitignore:68` 忽略的两个活动 openspec `tasks.md` 不计入）。**不得**执行 `git push origin`。

- [x] **Step 4: 更新本计划状态**

结果：本文件顶部已改为指向 `git log -1`（提交 hash 随本提交生成）；Task 1–5 复选框已按执行结果勾选，归档门控（Task 4 Step 3）保持未勾选，待新机验证完成后单独执行并回填。

---

## 自查记录（writing-plans self-review）

1. **覆盖检查**：用户要求的 4 类修正分别对应 Task 1（过期进度注记/13.5）、Task 2（面包屑计划回填）、Task 3（README 限制与状态）、Task 4（openspec 验证与归档门控）；"计划记录在哪里"由本文件与 Task 5 Step 1 回答；"变更与方案"在每个 Task 的"背景分析 + 具体替换文本"中给出。无缺口。
2. **占位符扫描**：无未完成占位标记；尖括号仅出现在"被替换的旧内容说明"与 `<host>` 这类明确占位说明中，均附取值来源。无空泛指令。
3. **类型/名称一致性**：提交 hash（`8ff8795`、`c882113`、`db1b676`、`2255681`、`7ead01d7130`）与 git 历史一致；文件路径、端口（8006/8088/8080/8500）、openspec 目录名在全文一致；远端名统一为 `mine`，禁止 `origin`。
