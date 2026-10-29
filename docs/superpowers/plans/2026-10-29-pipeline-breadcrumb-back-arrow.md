# 流水线详情页面包屑返回箭头 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让流水线执行详情页的面包屑区显示返回箭头（点击回流水线列表页），其余页面渲染与改前逐像素一致，并把改动按三个逻辑提交入库。

**Architecture:** 最小修复：`PipelineBreadCrumb.vue` 新增 `showBack: Boolean` prop 绕开 bk-breadcrumb 的 `back-router` 与 `#prefix` 插槽互斥，仅 `DetailHeader.vue` 启用。spec 见 `docs/superpowers/specs/2026-10-29-pipeline-breadcrumb-back-arrow-design.md`。

**Tech Stack:** Vue 2.5（bk-magic-vue）、eslint 7（项目自带配置）、webpack（dev server）、git。

---

## 前置说明（执行者必读）

1. **代码改动已在工作区**（未提交）。本计划主体是"验证 + 记录 + 提交"，不是重写代码。Task 1 先核对 diff 与预期完全一致。
2. **TDD 偏离声明**：本仓 devops-pipeline 无任何前端测试基建（`package.json` 无 test/lint 脚本、无 jest/mocha 约定）。为一个 ~12 行的纯渲染开关引入测试框架违反 spec 非目标与 YAGNI，故验证采用 spec 定义的三层（静态 eslint / dev server / 浏览器手工），此为有意偏离而非遗漏。
3. **浏览器验证的既知限制**（`docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md` 2026-10-27 续二已记录）：本地 docker 前端镜像是从 release 包产物 COPY 的，**不是**从 `src/frontend` 编译；dev server 若因依赖解析失败，按 Task 2 的止损路径降级。

## 文件结构

| 文件 | 责任 | 本计划动作 |
|---|---|---|
| `src/frontend/devops-pipeline/src/components/PipelineHeader/PipelineBreadCrumb.vue` | 面包屑组件渲染 | 核对已改 diff |
| `src/frontend/devops-pipeline/src/components/PipelineHeader/DetailHeader.vue` | 执行详情页头 | 核对已改 diff |
| `deploy/local/docker-compose.yml` | 本地部署编排 | 核对已改 diff（LANG） |
| `deploy/local/README.md`、`docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md`、`docs/superpowers/specs/2026-10-29-pipeline-breadcrumb-back-arrow-design.md` | 记录 | 核对/追加验证状态 |

---

## Task 1: 静态验证（diff 核对 + eslint）

**Files:**
- Modify: 无（只读核对）
- Test: `npx eslint` 实为 `./node_modules/.bin/eslint`（devops-pipeline 目录内）

- [x] **Step 1: 核对工作区 diff 与预期逐字一致**

Run（仓库根 `/home/xsg/aicode/bk-ci`）:
```bash
git diff src/frontend/devops-pipeline/src/components/PipelineHeader/
```
Expected——关键 hunk 必须是：

`PipelineBreadCrumb.vue`（3 处）:
```
-            :back-router="manageRoute"
+            :back-router="showBack ? manageRoute : null"
         >
-            <template #prefix>
+            <template
+                v-if="!showBack"
+                #prefix
+            >
```
```
+            // bk-breadcrumb 的 back-router 与 prefix 插槽互斥（prefix 存在时不渲染返回箭头），
+            // 故需要返回入口的页面显式打开 showBack：此时用箭头替换前缀的流水线图标
+            showBack: Boolean,
```
（位于 props 内 `showBuildNumSwitch: Boolean,` 之后）

`DetailHeader.vue`（1 处，在 `show-build-num-switch` 之后）:
```
+            show-back
```

任何其他 hunk 出现即为异常，停止并报告。

- [x] **Step 2: 跑 eslint**

Run（workdir `src/frontend/devops-pipeline`）:
```bash
./node_modules/.bin/eslint src/components/PipelineHeader/PipelineBreadCrumb.vue src/components/PipelineHeader/DetailHeader.vue; echo "exit=$?"
```
Expected: 仅有 Browserslist 数据过期警告（噪音，忽略），`exit=0`。（2026-10-29 已实测通过一次；本步为提交前复跑。）

## Task 2: 渲染验证（dev server，带止损）

**Files:**
- Modify: 无

- [ ] **Step 1: 启动 dev server**

Run（workdir `src/frontend/devops-pipeline`）:
```bash
npm run dev
```
Expected: webpack 编译成功并监听本地端口。
**止损**：若因 workspace 依赖缺失（`pnpm workspace:` 包无法解析等）编译失败——不要安装新包、不要改依赖——立即停止，在 Task 3 记录"渲染验证降级：dev server 不可用 + 失败原因"，跳到 Task 3。（既知根因：本机无 monorepo 安装链路，见前置说明 3。）

- [ ] **Step 2: 浏览器手工验收（人工步骤，由用户执行）**

清单：
- 流水线执行详情页：面包屑区出现返回箭头（替代原流水线小图标），点击回到本流水线的执行历史页（构建列表，URL 形如 `.../<pipelineId>/history/history`）；
- 编排/编辑页 / 执行记录页 / 预览页 / 调试执行头 / 导入页：仍为流水线 logo 前缀、无箭头。

把逐条结果交回，进入 Task 3 记录。

### 2026-10-29 验收轮 1 结果与设计修订

- 箭头出现 ✓；编排/执行记录/预览页无箭头有 logo ✓。
- 首轮箭头目标为流水线列表页，用户指出应回**构建列表（执行历史页）**——已修订：新增 `backRoute` prop（缺省 `manageRoute`），`DetailHeader` 传入 `pipelinesHistory` 路由（params: projectId+pipelineId）。eslint exit=0，dev server 增量编译通过，产物含 `historyRoute`。
- 轮 2 待复验：详情页点箭头应落在 `.../history/history`。（注意：HMR websocket 固定 `127.0.0.1:8006`，跨机不可达，复验前需手动强刷。）

## Task 3: 验证状态记录

**Files:**
- Modify: `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md`（文末追加小节）

- [ ] **Step 1: 在文末（2026-10-27 续二之后）追加**

```markdown
### 2026-10-29 返回箭头修复：验证状态

- eslint（devops-pipeline 自带配置）：两改动文件 exit=0。
- 渲染验证：<dev server 结果，或"降级：dev server 不可用（原因）">
- 浏览器手工验收：<逐条结果，或"未做：待前端编译链路补齐">
```

尖括号处按 Task 2 实际结果填写，不留空。

## Task 4: 提交（三个逻辑提交，顺序固定）

**Files:** 全部已在 Table "文件结构" 列出。

- [ ] **Step 1: 提交前端修复**

```bash
git add src/frontend/devops-pipeline/src/components/PipelineHeader/PipelineBreadCrumb.vue src/frontend/devops-pipeline/src/components/PipelineHeader/DetailHeader.vue
git commit -m "fix(frontend): 流水线详情页面包屑补回返回箭头（showBack 绕开 bk-breadcrumb prefix 互斥）"
```

- [ ] **Step 2: 提交 LANG 修正及其部署文档**

```bash
git add deploy/local/docker-compose.yml deploy/local/README.md
git commit -m "deploy: 后端容器 LANG/LC_ALL 修正为镜像内真实存在的 C.UTF-8，记录 JVM 编码根因与 mysql 显示误判提醒"
```

- [ ] **Step 3: 提交 superpowers 文档（spec + 两份 plan）**

```bash
git add docs/superpowers/specs/2026-10-29-pipeline-breadcrumb-back-arrow-design.md docs/superpowers/plans/2026-10-29-pipeline-breadcrumb-back-arrow.md docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md
git commit -m "docs: 新增面包屑返回箭头 spec 与实施计划；2026-10-20 部署计划补 10-27/10-29 记录"
```

- [ ] **Step 4: 确认工作区干净**

```bash
git status --short
```
Expected: 无输出。

---

## 自查记录（writing-plans self-review）

1. **Spec 覆盖**：目标→Task 1/2；验证三层→Task 1（静态）+ Task 2（渲染/手工）；回滚→无需任务（diff 小，不入库前 `git checkout` 即回滚）；提交分组→用户指定三块，Task 4 落实。无缺口。
2. **占位符**：无 TBD；Task 3 模板尖括号处由执行者以实测结果填充（数据来源已在步骤给出）。
3. **类型一致性**：`showBack` / `show-back` / `manageRoute` / `PipelineManageList` 在 spec、diff、任务中拼写一致；eslint 命令与工作目录一致。
