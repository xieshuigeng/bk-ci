# FFmpeg n9.1 可复现构建资产提交设计

日期：2026-11-25

## Intent / Why

用户希望把 FFmpeg n9.1 静态构建过程中形成的**脚本、代码、配置**也提交到仓库，目标是让其他人在新机器上**复现同样的全静态构建**，并能在 bk-ci 里重建/审计这条流水线。用户明确不提交：

- 构建产生的文件（二进制、tar、构建报告、校验和等）
- 拉取下来的 FFmpeg 源码及依赖源码
- 本地环境专属的 ID、IP、路径、凭据和渲染产物

因此本设计只提交“可复现的输入”，不提交“运行后的输出”。

## Goals

1. 仅凭仓库内容即可复现 FFmpeg `n9.1`、Linux x86_64、musl 全静态 `ffmpeg/ffprobe/ffplay`。
2. 保留 bk-ci 流水线配置的可审计形态：构建 → 上传制品 → 注册报告，且不含真实环境标识。
3. 明确区分“源文件”和“生成物”，让 `.gitignore` 能兜住后续本地构建产物。
4. 给出可执行的校验方式，确认三个产物是静态链接且版本为 `n9.1`。

## Non-goals / Anti-goals

- 不提交任何二进制、tar 包、`build-report.txt`、`checksums.txt`。
- 不提交 FFmpeg / x264 / x265 / libvpx 等上游源码或 Alpine rootfs、依赖缓存。
- 不提交真实 `pipelineId`、`projectId`、项目代号、artifactory IP、网关地址、agent ID/密钥。
- 不修改 bk-ci 源码；这里只增加工具与文档资产。
- 不把 `/home/xiesg/test/bkci-local-stash`、`deploy/local/rendered/`、`.env`、凭据类文件纳入提交。

## Constraints

- 现有 `tools/ffmpeg-build/` 已提交：`Dockerfile`、`README.md`、`.gitignore`、`scripts/build-in-container.sh`、`test/ffplay_enabled_test.sh`。本次在该目录扩展，不另起目录。
- 流水线模型当前只存在于 bk-ci 本地和 `/tmp/opencode/ffmpeg_pipe2.json`；其中 `e-build` 步骤把内层构建脚本以 base64 内联，`e-upload-*` 步骤包含本地 artifactory/gateway 地址与环境默认值。
- 内层构建脚本 `scripts/build-in-container.sh` 已经是静态构建的真实来源；不应在流水线模板里再维护一份副本，避免漂移。
- 仓库根 `.gitignore` 已忽略 `bin/`、`out`、`*.tar.gz`；`tools/ffmpeg-build/.gitignore` 已忽略 `out/`、`out.dynamic-*/`、`*.tar.gz`、`*.log`。

## Approaches considered

### A. 最小可复现集

只提交构建源码、Dockerfile、测试、README、校验脚本和计划文档。
优点：最干净，没有环境细节。缺点：无法在 bk-ci 中重建“构建→上传→注册报告”整条链路。

### B. A + 脱敏流水线模板

在 A 之上增加 `tools/ffmpeg-build/pipeline/`：流水线 JSON 模板、外层编排脚本、渲染脚本、流水线 README 和模板测试。
优点：既能本地复现静态构建，也能审计/重建 bk-ci 流水线；环境值全部占位符化。缺点：多一层渲染步骤，模板需要随脚本变化重新生成。

### C. A + 轻量证据文本

在 A 之上提交 `build-report.txt` / `checksums.txt`。
优点：留审计痕迹。缺点：用户明确不要构建产物；且对应二进制不在仓库里，证据价值有限。

**用户已选 A+B。** C 不采纳。

## Decisions（已定）

### 目录

沿用并扩展：

```text
tools/ffmpeg-build/
  Dockerfile                         # 已提交，不改
  README.md                          # 修改：补充 verify 与 pipeline 用法
  .gitignore                         # 修改：忽略渲染后的流水线文件
  scripts/
    build-in-container.sh             # 已提交，不改
    verify-static.sh                  # 新增
  test/
    ffplay_enabled_test.sh            # 已提交，不改
  pipeline/
    README.md                         # 新增
    ffmpeg-pipeline.template.json     # 新增，占位符版
    render_pipeline.py                # 新增
    scripts/
      build-in-bkci.sh                # 新增，外层编排脚本
    test/
      render_pipeline_test.sh         # 新增
    .gitignore                        # 新增或并入上级 .gitignore：忽略 rendered/
```

文档位置：

- 本设计：`docs/superpowers/specs/2026-11-25-ffmpeg-n91-build-assets-design.md`
- 验证/证据日志继续放在：`docs/requirements/2026-11-20-ffmpeg-source-build-plan.md`（追加一小节，不重写历史）

### 新增/修改内容

1. `scripts/verify-static.sh`
   - 入参：产物目录，默认 `tools/ffmpeg-build/out`。
   - 检查 `bin/ffmpeg`、`bin/ffprobe`、`bin/ffplay` 三个文件存在且可执行。
   - `file` 输出必须含 `statically linked`；`ldd` 必须报告 `not a dynamic executable`。
   - 三个 `-version` 输出必须含 `n9.1`。
   - 若存在 `checksums.txt` 则顺带 `sha256sum -c`，但**不要求**该文件存在（因为它属于生成物，不提交）。

2. `pipeline/scripts/build-in-bkci.sh`
   - 从当前 `e-build` 步骤抽出外层逻辑：准备 workspace、下载 Alpine minirootfs、安装 apk 构建依赖、调用内层 `build-in-container.sh`、收集产物。
   - 不内联内层脚本源码；由渲染脚本负责把 `scripts/build-in-container.sh` 以 base64 形式注入到最终流水线 JSON，保持单一来源。
   - 保留 `GIT_PROXY_PREFIX`、`FFMPEG_TAG`、`FFMPEG_COMMIT_EXPECTED`、`JOBS`、`OUT_HOST` 等环境变量入口。

3. `pipeline/ffmpeg-pipeline.template.json`
   - 以当前 `ffmpeg-build-n9.1` 流水线为蓝本，但移除/替换真实环境值：
     - `pipelineId` → `__PIPELINE_ID__`
     - `projectId` / `demotest` → `__PROJECT_ID__` / `__PROJECT_CODE__`
     - `http://172.17.0.5:21920` → `__ARTIFACTORY_BASE_URL__`
     - `http://172.28.0.1:8080` → `__BK_CI_GATEWAY__`
     - 真实 pipeline ID 默认值 → `${BK_CI_PIPELINE_ID}`
   - 保留结构：manual trigger + `build-ffmpeg` 容器 + `e-build` / `e-upload-artifact` / `e-upload-report`。
   - `e-build.script` 写成 `@file:pipeline/scripts/build-in-bkci.sh` 占位；渲染时替换为脚本正文，并把内层脚本以 `@base64:scripts/build-in-container.sh` 注入。
   - `e-upload-*` 只保留环境变量名，不保留任何密钥值。

4. `pipeline/render_pipeline.py`
   - 输入：`ffmpeg-pipeline.template.json` + 一组占位符值（命令行参数或环境变量）。
   - 输出：`ffmpeg-pipeline.json`（默认写到 `pipeline/rendered/`，被忽略）。
   - 行为：替换 `__*__`、`@file:*`、`@base64:*`；输出前断言不含 `172.`、`p-8bb...`、`demotest`、`secret key` 字面量真值。

5. `pipeline/test/render_pipeline_test.sh`
   - 用一组假占位符值渲染一次到临时目录。
   - 断言：生成的 JSON 可被 `python3 -m json.tool` 解析；不含 `__`、`@file:`、`@base64:`；不含真实 IP/ID/项目代号。
   - 断言：内层脚本 base64 能解出与 `scripts/build-in-container.sh` 完全一致的内容。

6. `README.md` 与 `docs/requirements/2026-11-20-ffmpeg-source-build-plan.md`
   - README 增加两条路径：`docker build/run` 本地复现；`render_pipeline.py` 生成 bk-ci 可导入 JSON。
   - 计划文档追加“2026-11-25 可复现资产提交范围”，引用本设计，不重复大段证据。

7. `.gitignore`
   - 增加 `pipeline/rendered/`（或 `pipeline/ffmpeg-pipeline.json`），确保渲染产物不进仓库。

## What is explicitly not committed

```text
/data/bkci-local/ffmpeg-out/**          # 3 个二进制、tar、build-report.txt、checksums.txt
tools/ffmpeg-build/out.dynamic-*/**     # 本地动态对照构建目录（已忽略）
tools/ffmpeg-build/out/**               # 本地构建输出（已忽略）
**/*.tar.gz, **/*.log                   # 源码包/日志（已忽略/应忽略）
alpine-rootfs/, deps-cache/, work/src/  # rootfs、依赖缓存、FFmpeg 源码
/tmp/opencode/ffmpeg_pipe*.json         # 含真实环境值的原始流水线导出
/tmp/opencode/*.b64, ffmpeg_ebuild.sh   # 中间生成物
/home/xiesg/test/bkci-local-stash/**     # 外部 stash，可能有明文凭据
deploy/local/rendered/**, .env, 凭据文件
真实 pipelineId / projectId / IP / agent secret / 网关地址
```

## Verification after implementation（提交前）

- `tools/ffmpeg-build/test/ffplay_enabled_test.sh`：4/4 PASS。
- `pipeline/test/render_pipeline_test.sh`：PASS，且模板干净。
- `tools/ffmpeg-build/scripts/verify-static.sh /data/bkci-local/ffmpeg-out`：PASS（用本地已有产物做校验，产物本身不提交）。
- `git diff --check` 无输出。
- `git status --short` 只包含上面列出的新增/修改文件；`out.dynamic-*`、`ffmpeg-out`、stash、渲染 JSON 均不出现。
- 提交到 `master`，推送 `mine master`，不推送 `origin`。

## Size and next step

规模：小到中等，主要是文档/模板/两个脚本和一个测试，无业务代码改动。按 short design 处理，不做 builder check。

下一步：用户批准本设计后，调用 `superpowers:writing-plans` 生成实施计划，再按计划执行；**在批准前不提交任何新增文件**。
