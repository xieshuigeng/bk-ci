# 本地部署图标永久修复设计（2026-11-25）

## 意图与原因

本地 bk-ci 部署中，研发商店的插件/模板/镜像、平台管理的源代码管理等页面大量图标为空。用户希望一次性从仓库层面解决，不再每次重建环境后手工修补。

## 已确认的根因

- 图标 URL 指向 `/ms/artifactory/.../file/png/*.png`，映射到 artifactory 容器内 `/data/bkce/public/ci/artifactory/file/png/`；该目录不存在， curl 返回 500 `No such file or directory`。
- 31 个内置图标已在仓库 `support-files/file/png/` 且镜像内也带了一份，但本地 compose 没有执行官方 `bk-ci-setup.sh` 的 `setup_ci_artifactory()` 复制步骤。
- 现有 `deploy/local/fix-atom-logos.sh` 能修，但必须手工重跑，容器/数据卷重建后复发。
- 另有 12 个仓库内不存在的引用：9 个 zip 直装插件的哈希 PNG、社区包缺失的 `tapdTrigger.png`/`scmGitTrigger.png`、以及 `support-files/file/svg/code-SVN.svg` 未放到 artifactory 目录。
- 源代码管理的 TGIT 图标 URL 在仓库 SQL 种子中拼错（`%2Ffile%png%2F` 缺 `2F`），即使补齐文件仍返回 400。

## 目标 / 非目标

- 目标：本地部署启动后，数据库中所有指向本地 artifactory 的图标 URL 均返回 200；图标资产与播种逻辑全部在 git 仓库中；重建容器后无需人工介入。
- 非目标：不改上游前端源码语义、不改真实 SaaS 发布流程、不追求 9 个插件图标使用官方原图（用仓库已有图标作为通用图）、不修改 Dockerfile/上游镜像。

## 方案比较

1. **自动播种 + 提交图标（选用）**：compose 在 artifactory 启动时把镜像内置 `support-files/file` 和仓库补充图标复制到存储根；提交 12 个缺失图标与 TGIT SQL 修正；加 URL 校验测试。永久、幂等，代价是插件图标为通用图。
2. 自动播种 + 重建前端镜像：再用 `AtomLogo` 兜底覆盖任何缺失图标，最稳但要重做前端镜像，超出本次问题根因。
3. 只重建前端回退：请求仍 500，不修根因，弃用。

## 实现要点

- 新增 `deploy/local/seed-artifactory-icons.sh`：解析 `rendered/etc/ci/application-artifactory.yml`（容器内优先 `/etc/bkci/conf/application-artifactory.yml`）的 `archiveLocalBasePath`，复制镜像内 `/data/workspace/support-files/file/.` 与挂载的补充图标目录到 `<base>/file/`，`cp -r --update=none` 幂等且不覆盖同名文件。
- 新增 `deploy/local/icon-assets/`：`png/` 放 `tapdTrigger.png`、`scmGitTrigger.png`；`svg/code-SVN.svg` 从 `src/frontend/svg-sprites/devops/` 复制；9 个哈希图标放在 `icon-assets/` 根目录，因为 DB URL 双重解码后指向 `<base>/file/$hash.png` 而非 `<base>/file/png/$hash.png`；这些图标用仓库已有 PNG 作通用图。
- 修改 `deploy/local/docker-compose.yml`：仅覆盖 `artifactory` 服务的 `command`/`volumes`，启动时先执行播种脚本再 `exec /entrypoint.sh artifactory`；保留原有配置与 entrypoint 挂载。
- 修正 `support-files/sql/5001_init_dml/5001_ci_repository-init_dml_mysql.sql` 中 TGIT 的 `LOGO_URL` 编码；当前运行的库执行一次等价 UPDATE（不属于提交物）。
- 新增 `deploy/local/test/icon-urls-test.sh`：从 MySQL 收集所有 artifactory 图标 URL，逐个经网关 curl，断言 200；作为可重复验收。
- 更新 `deploy/local/README.md`：说明自动播种、补充图标来源、验收命令；`fix-atom-logos.sh` 保留为手工兜底但注明常规场景不再需要。

## 实现裁决（2026-11-25）

- URL 校验只收集以 `/ms/artifactory/` 开头的值：`T_SERVICE.logo_url` 中有字面量 `artifactory` 占位符，不是可请求路径。
- `EXTRA_SRC=/opt/icon-assets` 在 compose `command` 中以内联环境变量传给播种脚本，不覆盖 `x-backend` 继承的 `environment` 映射，避免丢失 JVM/Consul 配置。
- 9 个哈希插件图标播种到 `<base>/file/` 根目录，2 个触发图与 SVG 保持 `png/`、`svg/` 子目录；路径由失败响应体中的实际读取路径确认。
- `cp -n` 改为 GNU `cp -r --update=none`：镜像内 coreutils 对 `-n` 输出非便携性警告，两者语义相同（不覆盖已存在文件）。
- 当前运行库对 TGIT 执行一次等价 UPDATE；提交物只包含修正后的 SQL 种子，不包含运行态数据。

## 约束与验证

- 不提交任何凭据、运行日志、下载产物；图标仅来自仓库已有素材。
- 验证：重建 artifactory 容器 → 运行 `seed_icons_test.sh` 与 `icon-urls-test.sh` 全部通过 → `git diff --check` 干净 → 提交并推送 `mine master`。
