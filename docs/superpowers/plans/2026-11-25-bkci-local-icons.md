# 本地部署图标永久修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 本地 bk-ci 部署启动后，所有指向本地 artifactory 的图标 URL 均返回 200，且无需每次重建环境后手工补齐。

**Architecture:** 在 artifactory 容器启动时运行幂等播种脚本，把镜像内置 `support-files/file` 与仓库提交的补充图标复制到 artifactory 存储根；修正上游 SQL 种子中的 TGIT URL 拼写；增加全量 URL 校验脚本与单元测试。

**Tech Stack:** Bash、Docker Compose、MySQL 8、curl、Python 3（测试辅助）

**Spec:** `docs/superpowers/specs/2026-11-25-bkci-local-icons-design.md`

## Global Constraints

- 只修改 `deploy/local/`、`support-files/sql/`、`docs/`；不改上游前端/后端源码。
- 不提交凭据、日志、下载产物或临时目录内容；补充图标必须来自仓库已有素材。
- 插件图标允许使用仓库已有 PNG 作为通用图，不要求官方原图。
- 校验口径：经网关 `http://localhost:8080` 请求所有 artifactory 图标 URL，HTTP 200 为通过。
- 远程仅推送 `mine master`，不得使用 `origin`。

## Review Focus

- 播种脚本在空存储根上必须创建 `<base>/file/png/*.png` 与 `<base>/file/svg/*.svg`，层级错误仍会 500；由 Task 1 的 `seed_icons_test.sh` 断言精确路径。
- 重复播种必须幂等、不覆盖用户上传的同名文件；由 Task 1 重复执行并校验内容不变。
- 9 个哈希命名插件图标与 2 个 SaaS 触发图缺失时页面仍空；由 Task 2 的全量 URL 测试覆盖全部 DB 引用。
- TGIT 的 SQL 种子拼写错误必须修正且当前运行库同步修正；由 Task 2 的 URL 测试断言 TGIT 200。
- 容器重建后自动生效，而不是依赖 `fix-atom-logos.sh` 手工执行；由 Task 2 强制重建 artifactory 后运行测试验证。

---

### Task 1: 补充图标资产与幂等播种脚本

**Files:**
- Create: `deploy/local/icon-assets/png/*.png`（12 个）
- Create: `deploy/local/icon-assets/svg/code-SVN.svg`
- Create: `deploy/local/seed-artifactory-icons.sh`
- Create: `deploy/local/test/seed_icons_test.sh`

**Interfaces:**
- Consumes: `support-files/file/png/*.png`（31 个内置图标）、`src/frontend/svg-sprites/devops/code-SVN.svg`、审计得到的 9 个哈希文件名。
- Produces: `seed-artifactory-icons.sh`，支持 `ARTIFACTORY_BASE`、`BUILTIN_SRC`、`EXTRA_SRC` 三个环境变量；默认从 `rendered/etc/ci/application-artifactory.yml` 解析 `archiveLocalBasePath`，默认 `BUILTIN_SRC=/data/workspace/support-files/file`，默认 `EXTRA_SRC=<脚本目录>/icon-assets`。
- Produces: 复制结果位于 `$ARTIFACTORY_BASE/file/`，`cp -n` 幂等。

- [ ] **Step 1: 写失败测试**

创建 `deploy/local/test/seed_icons_test.sh`：
- `TMP="$(mktemp -d)"`，创建空的 `$TMP/root`、`$TMP/builtin/png`；
- 在 `$TMP/builtin/png/manualTrigger.png` 放内容 `builtin`；
- 设 `ARTIFACTORY_BASE=$TMP/root`、`BUILTIN_SRC=$TMP/builtin`、`EXTRA_SRC=<repo>/deploy/local/icon-assets` 运行播种脚本；
- 断言 `$TMP/root/file/png/manualTrigger.png` 内容为 `builtin`；
- 断言 9 个哈希 PNG、`tapdTrigger.png`、`scmGitTrigger.png`、`$TMP/root/file/svg/code-SVN.svg` 均存在；
- 再次运行脚本，断言仍全部存在且内容不变。

- [ ] **Step 2: 运行测试确认失败**

Run: `bash deploy/local/test/seed_icons_test.sh`
Expected: FAIL，缺少 `deploy/local/seed-artifactory-icons.sh` 或图标资产。

- [ ] **Step 3: 创建图标资产**

- 从 `support-files/file/png/` 复制 11 个 PNG 到 `deploy/local/icon-assets/png/`，文件名按下表（源 → 目标）：
  `WEB.png` → `$767ada6b0e2e4386a13358e774db7968.fe66657226bf4aecaeaae7dc1fdbc6ed2615706359136887281.png`（checkout）、
  `linuxScript.png` → `$5e460010399f4830a278fb9e2f5eab83.fbea4a4ba5874eae9d0b0701ceeacfda3624650039460249707.png`（run）、
  `codeCC.png` → `$abeeac484fa3443b85ccd46df464f820.38ea1b78ed99486f9880d902ec06f6102041862906458429696.png`、
  `singleArchive.png` → `$7a2e7e4050d14b6a914851c71e1af2f0.acdfea3291d44aa6a12f473cbafd4f2613985901947735757165.png`、
  `buildArchiveGet.png` → `$5ade6e3f4ca944c9a32579c4a7e4a960.f3898709a5ac44b98db93d78c56b5e4c11512219954973507074.png`、
  `reportArchive.png` → `$2ae6c0dea835446ba80b45b4c6d031ac.35e612f73d7f4d07bed3f414263b50478641439530655324090.png`、
  `SERVER.png` → `$d82314ef4d054eb3b178bbe92ca216b7.2f3fcdb3c8f14a4bae6230a57e4a46683083259447872393921.png`、
  `codeP4.png` → `$987a00c12e5843399df1d33090900dc1.d4369feb966f40eb8cec2c02434671a52426503237734807673.png`、
  `subPipelineCall.png` → `$e9c05e98e5824e859a3c0d715901afbb.71ed59183d154d2795eb9219029133a013030099571157024121.png`、
  `manualTrigger.png` → `tapdTrigger.png`、
  `githubTrigger.png` → `scmGitTrigger.png`；
- `CODE_SVN.png` 由内置目录提供，不重复提交。
- 复制 `src/frontend/svg-sprites/devops/code-SVN.svg` 到 `deploy/local/icon-assets/svg/code-SVN.svg`。

- [ ] **Step 4: 实现播种脚本**

创建 `deploy/local/seed-artifactory-icons.sh`：`set -euo pipefail`；按 Interfaces 解析三个环境变量；“若 `ARTIFACTORY_BASE` 为空则从 `rendered/etc/ci/application-artifactory.yml` 用 `grep -m1 archiveLocalBasePath | awk '{print $2}'` 解析，为空则报错退出”；`mkdir -p "$ARTIFACTORY_BASE/file"`；用 `cp -rn "$BUILTIN_SRC/." "$ARTIFACTORY_BASE/file/"` 复制内置图标（源不存在时容错跳过），再用 `cp -rn "$EXTRA_SRC/." "$ARTIFACTORY_BASE/file/"` 复制补充图标；打印复制后的文件数量。

- [ ] **Step 5: 运行测试确认通过**

Run: `bash deploy/local/test/seed_icons_test.sh`
Expected: PASS（含重复执行幂等断言）。

- [ ] **Step 6: 提交**

```bash
git add deploy/local/icon-assets deploy/local/seed-artifactory-icons.sh deploy/local/test/seed_icons_test.sh
git commit -m "test: add idempotent artifactory icon seeding"
```

---

### Task 2: Compose 自动播种、SQL 种子修正与全量 URL 验收

**Files:**
- Modify: `deploy/local/docker-compose.yml`（仅 `artifactory` 服务）
- Modify: `support-files/sql/5001_init_dml/5001_ci_repository-init_dml_mysql.sql`（TGIT 行）
- Create: `deploy/local/test/icon-urls-test.sh`

**Interfaces:**
- Consumes: Task 1 的 `seed-artifactory-icons.sh` 与 `icon-assets/`。
- Produces: artifactory 容器启动时自动执行播种；全量 URL 测试脚本从 MySQL 收集所有含 `artifactory` 的图标 URL 并逐个经网关校验。

- [ ] **Step 1: 写失败测试**

创建 `deploy/local/test/icon-urls-test.sh`：
- 用 `docker exec bkci-mysql mysql -uroot -proot123 -N -B` 查询 `information_schema.columns` 得到所有 `devops%` 库中列名匹配 `icon|logo` 的表列；
- 对每个列查询非空且含 `artifactory` 的值，去重；
- 对每个 URL 用 `curl -s -o /dev/null -w '%{http_code}' -H 'X-DEVOPS-UID: admin' -H 'X-DEVOPS-TOKEN: devops' "http://localhost:8080$url"`；
- 断言每个 URL 的 HTTP 码为 200，任一非 200 打印 URL 与状态码并退出 1；最后打印 `icon_urls_test: PASS (<N> urls)`。

- [ ] **Step 2: 运行测试确认失败**

Run: `bash deploy/local/test/icon-urls-test.sh`
Expected: FAIL，输出多个 500/400 URL（当前存储根无 `file/` 且 TGIT URL 拼错）。

- [ ] **Step 3: 修改 compose 与 SQL 种子**

- `deploy/local/docker-compose.yml` 的 `artifactory` 服务覆盖 `command` 为 `/bin/bash -c` 执行 `/bin/bash /seed-icons.sh` 后 `exec /bin/bash /entrypoint.sh artifactory`；覆盖 `volumes` 时保留原有 `./rendered/etc/ci:/etc/bkci/conf:ro` 与 `./entrypoint-service.sh:/entrypoint.sh:ro`，新增 `./seed-artifactory-icons.sh:/seed-icons.sh:ro`、`./icon-assets:/opt/icon-assets:ro`；通过 env `EXTRA_SRC=/opt/icon-assets` 传入补充图标目录。
- `support-files/sql/5001_init_dml/5001_ci_repository-init_dml_mysql.sql` 中 TGIT 行的 `LOGO_URL` 把 `%2Ffile%png%2FcodeTGit.png` 改为 `%2Ffile%2Fpng%2FcodeTGit.png`。

- [ ] **Step 4: 使当前运行库与容器生效**

```bash
cd deploy/local
docker exec bkci-mysql mysql -uroot -proot123 -e "UPDATE devops_ci_repository.T_REPOSITORY_SCM_PROVIDER SET LOGO_URL=REPLACE(LOGO_URL,'%2Ffile%png%2F','%2Ffile%2Fpng%2F') WHERE PROVIDER_CODE='TGIT';"
docker compose up -d --force-recreate artifactory
sleep 20
```

Expected: artifactory 容器重新创建，启动日志包含播种输出；该 UPDATE 是一次性运行态修复，不属于提交物。

- [ ] **Step 5: 运行测试确认通过**

Run: `bash deploy/local/test/icon-urls-test.sh`
Expected: PASS，所有 URL 返回 200。

- [ ] **Step 6: 提交**

```bash
git add deploy/local/docker-compose.yml support-files/sql/5001_init_dml/5001_ci_repository-init_dml_mysql.sql deploy/local/test/icon-urls-test.sh
git diff --check
git commit -m "fix: seed artifactory icons automatically on startup"
```

---

### Task 3: 文档、整体验证与推送

**Files:**
- Modify: `deploy/local/README.md`
- Modify: `docs/superpowers/specs/2026-11-25-bkci-local-icons-design.md`（如需记录裁决）
- Commit: `docs/superpowers/specs/2026-11-25-bkci-local-icons-design.md`、`docs/superpowers/plans/2026-11-25-bkci-local-icons.md`

**Interfaces:**
- Consumes: Task 1/2 的脚本与验收结果。

- [ ] **Step 1: 更新文档**

在 `deploy/local/README.md` 的图标排障节追加：启动自动播种说明、补充图标来源、新测试命令 `bash deploy/local/test/icon-urls-test.sh`、`fix-atom-logos.sh` 仅作手工兜底、TGIT SQL 种子已修正。

- [ ] **Step 2: 全量验证**

```bash
bash deploy/local/test/seed_icons_test.sh
bash deploy/local/test/icon-urls-test.sh
git diff --check
git status --short --untracked-files=all
```

Expected: 两个测试 PASS，`git status` 只有预期文档改动（提交后为空）。

- [ ] **Step 3: 提交并推送**

```bash
git add deploy/local/README.md docs/superpowers/specs/2026-11-25-bkci-local-icons-design.md docs/superpowers/plans/2026-11-25-bkci-local-icons.md
git diff --cached --check
git commit -m "docs: document automatic icon seeding"
git fetch mine master
git diff --check
git push mine master
git rev-parse HEAD
git rev-parse mine/master
```

Expected: `HEAD == mine/master`，工作区干净。
