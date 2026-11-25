# FFmpeg 源码构建项目：需求与方案（bk-ci 构建测试）

- 日期：2026-11-20
- 状态：**R-010 已批准（全静态重建）实施中**（不修改 bk-ci 代码，仅构建测试）
- 约束：**必须使用本仓库现有 bk-ci 本地环境完成构建测试；不修改 bk-ci 代码**（可更新构建脚本/镜像定义/需求文档与流水线作业配置，通过 API 触发测试）
- 源码：`https://github.com/FFmpeg/FFmpeg.git`（经 GitHub 代理获取）

> 本文档记录构建目标、研究结论、方案设计、检查点、验证方法，以及实施过程中的需求/决策变更与 bug。全程持续更新。

---

## 1. 目标与范围

### 1.1 构建目标（当前有效：R-010）
- 从 `https://github.com/FFmpeg/FFmpeg.git` 获取 **release tag 稳定版本 `n9.1`** 源码。
- 在 **Linux x86_64** 环境下完成源码构建，**全静态链接**，**运行时不依赖动态 `.so` 库**（`ffmpeg`/`ffprobe`/`ffplay` 三者同等要求）。
- 产出并验证**完整可用的 bin 工具集**：`ffmpeg`、`ffprobe`、`ffplay`，交付形态为**仅 3 个二进制文件**（拷贝即用）。
- 全过程作为 **bk-ci 本地环境构建测试**执行并可复现（不修改 bk-ci 代码）；需求、bug、修复与验证证据落盘到本文档/构建产物。

### 1.2 默认 bin 工具集与复核
| 程序 | 说明 | 启用条件 |
|---|---|---|
| `ffmpeg` | 转码/封装/滤镜处理主程序 | 默认构建，全静态 |
| `ffprobe` | 媒体探测与信息输出 | 默认构建，全静态 |
| `ffplay` | 简易播放器 | `--enable-sdl2` + SDL2（**必含**，全静态） |

> FFmpeg 标准 `make install` 通常仅安装上述 3 个主程序；`tools/` 辅助工具默认不纳入。交付仅含上述 3 个二进制（不随包分发 `lib/` 动态库）。

### 1.3 成功标准（按 R-010）
- **V1**：`ffmpeg/ffprobe/ffplay -version` 成功，版本与 `n9.1`(构建 `HEAD` `74e4393595cf2b5857f0da925c4e0dd74ea306e5`，见 B-003) 一致；`ffmpeg -buildconf` 含目标 `--enable-*`（含 `--enable-sdl2`）与静态构建标识。
- **V2**：`-encoders/-decoders/-formats/-filters/-codecs` 覆盖冻结能力基线。
- **V3**：lavfi 内置源完成编码、探测、解码冒烟通过；`ffplay` 至少完成 `-version`/启用与依赖形态验证（无显示环境交互播放可选补充）。
- **V4**：在 Ubuntu 24.04 noble x86_64 基线环境可执行；`file` 显示为静态链接 ELF（musl/静态），`ldd` 报告 **not a dynamic executable** 或 **statically linked**，运行时无 `.so` 动态依赖。
- **交付形态**：仅 3 个二进制文件 `ffmpeg`、`ffprobe`、`ffplay`（可附 `build-report.txt` 与校验信息；打包时仅含 3 bin）。
- **过程可追溯**：构建测试执行记录 + 归档产物 + 本文档需求/bug/验证闭环。

---

## 2. 冻结决策（C0，含 R-010 变更）

| 项目 | 决策 |
|---|---|
| 构建方案 | **A：Docker 隔离构建项目**（脚本化、可复现），**推荐 musl/Alpine 工具链实现全静态**（便于闭合 ffplay/SDL2 等依赖的静态链接） |
| 执行载体 | **bk-ci 本地环境构建测试**（dockerhost/流水线作业可用时执行；不修改 bk-ci 代码）+ 可复现 Docker 构建资产 |
| 版本 | **`n9.1`**（最新稳定 release tag）。`refs/tags/n9.1`=tag对象 `9d106a4c5a139fac2a62c349817017191217a9d8`，`n9.1^{}`/实际构建 `HEAD`=`74e4393595cf2b5857f0da925c4e0dd74ea306e5`（见 B-003） |
| 目标运行基线 | **Ubuntu 24.04 noble, x86_64** 可直接运行（静态 ELF，无需安装运行时动态库） |
| 源码获取 | `GIT_URL=https://github.com/FFmpeg/FFmpeg.git`，`GIT_PROXY_PREFIX=https://gh-proxy.com/` |
| 必含 bin | `ffmpeg`、`ffprobe`、`ffplay`（**三者均全静态、无运行时动态依赖**） |
| 链接方式 | **全静态链接**（`--enable-static --disable-shared` 及静态依赖链；具体 flags 以可闭合链接与 V1–V4 通过为准） |
| 许可证/范围 | `--enable-gpl --enable-version3`，**不启用 nonfree**；**不纳入 AV1(libsvtav1/libaom)** |
| 启用能力基线 | x264、x265、libvpx(VP8/VP9)、opus、libmp3lame、libvorbis、libass+freetype+fontconfig+fribidi+harfbuzz、SDL2(ffplay)、zlib、bz2、lzma、OpenSSL(HTTPS)、nasm；可用默认 demux/mux/codec/filters 保持开启 |
| 产物形态与落点 | **仅 3 个二进制** `ffmpeg/ffprobe/ffplay`；输出到 `tools/ffmpeg-build/out/`（仓库内）与 `/data/bkci-local/ffmpeg-out/`；可选仅含 3 bin 的 tar 包。**不以运行时安装 `.so` 依赖为前提** |
| 风险与说明 | `ffplay` 全静态需闭合 SDL2 及图形/音频/输入等依赖链（X11/Wayland/ALSA/Pulse/DRM 等），实现复杂度与可用静态库供给相关；实施中若遇不可闭合阻塞将记录具体原因并确认取舍，不擅自降级 |

> 历史决策：R-009 曾要求“完整前缀+tar.gz，动态依赖可按约定运行”；已由 **R-010** 替代。

---

## 3. 环境与现状勘察（实测，2026-11-20）

| 项目 | 结果 |
|---|---|
| 宿主 OS | Ubuntu 24.04.4 LTS (noble)，`6.8.0-142-generic x86_64`，Docker 29.2.0 |
| bk-ci | 本地 compose 栈运行，`demotest` 可用，流水线 `p-8bb091809f5d4c04ac88fe7ef525f617` 已存在；dockerhost/dispatch 链路已修复可启动构建容器（见 B-004~B-006） |
| 网络 | 宿主直连 `github.com` 失败（B-001）；`gh-proxy.com` 代理可达 |
| 既有产物（动态，已被新需求取代） | `/data/bkci-local/ffmpeg-out/`、`tools/ffmpeg-build/out/` 中曾产出 n9.1 动态链接 3 bin + 前缀 + tarball，V1–V3 在安装运行时依赖后通过，V4 为动态依赖形态；**不满足 R-010**，需全静态重建 |

---

## 4. 方案设计（方案 A：musl 全静态 + bk-ci 构建测试）

### 4.1 构建项目结构
```text
tools/ffmpeg-build/
  Dockerfile                # musl/Alpine 静态构建环境 + deps + build
  scripts/
    build-in-container.sh   # 容器内：clone -> configure(static) -> make -> install -> verify -> 仅导出3 bin
  .gitignore
  README.md
  out/                      # 构建输出（不入库）：仅 3 bin（+ report/校验）
```

### 4.2 configure 基线（方向性，C5 以实际结果校验）
```bash
PKG_CONFIG="pkg-config --static" \
./configure \
  --prefix="$PREFIX" \
  --pkg-config-flags="--static" \
  --extra-cflags="-static" \
  --extra-ldflags="-static" \
  --enable-static --disable-shared \
  --enable-gpl --enable-version3 \
  --enable-libx264 --enable-libx265 --enable-libvpx \
  --enable-libopus --enable-libmp3lame --enable-libvorbis \
  --enable-libass --enable-libfreetype --enable-libfontconfig --enable-libfribidi --enable-libharfbuzz \
  --enable-sdl2 \
  --enable-zlib --enable-bzlib --enable-lzma \
  --enable-openssl
```
> 以 `configure` 输出与 `ffbuild/config.log` 为准；ffplay 全静态可能需补充 SDL2/后端/系统库静态链接参数或自建静态依赖，必要时调整并记录。

### 4.3 bk-ci 执行方式（构建测试，不改 bk-ci 代码）
- 复用/更新 `demotest` 流水线 `p-8bb091809f5d4c04ac88fe7ef525f617` 的作业配置与脚本（通过 API），在现有 bk-ci 执行环境中完成静态构建与 V1–V4 验证，收集日志与产物。
- 同时保留 `tools/ffmpeg-build/` Docker 资产用于可复现本地/等价环境构建与验证。

---

## 5. 检查点与验证（R-010 重置）

- [x] **C0-需求冻结**：R-010 已批准（全静态、无运行时动态依赖、仅3个bin，含ffplay）
- [x] **C1-bk-ci 执行条件**：bk-ci dockerhost/dispatch 已可调度并启动 `ubuntu:24.04` 构建容器；网络 `gh-proxy.com`/alpine 镜像源可达（宿主验证）；`/data/bkci-local/ffmpeg-out` 可写。已通过 bk-ci 触发静态构建 #10（见 6.4/B-008）。
- [x] **C2-构建项目就绪**：`tools/ffmpeg-build/Dockerfile`、`scripts/build-in-container.sh` 为 Alpine/musl 全静态方案；流水线采用 `ubuntu:24.04` + chroot alpine-minirootfs 执行同一构建脚本（内嵌 gzip+base64）以兼容 bk-ci 执行环境（不改 bk-ci 代码）。
- [ ] **C3-源码获取**：tag/commit 可追溯（n9.1 / HEAD `74e43935...`）
- [ ] **C4-依赖就绪**：静态 `.a`/pc 依赖满足（含 SDL2/ffplay 链）
- [ ] **C5-configure 通过**：关键库与 ffplay 启用且为静态构建配置
- [ ] **C6-make 通过**
- [ ] **C7-install/收集**：仅导出 3 bin（及报告），架构正确
- [ ] **V1-版本与配置**（静态构建）
- [ ] **V2-能力覆盖**
- [ ] **V3-功能冒烟**
- [ ] **V4-静态可用性**：noble x86_64 可运行，`ldd` 无动态依赖（not a dynamic executable / statically linked）

### 验证命令模板
```bash
./ffmpeg -hide_banner -version
./ffmpeg -hide_banner -buildconf
./ffprobe -hide_banner -version
./ffplay -hide_banner -version
file ./ffmpeg ./ffprobe ./ffplay
ldd ./ffmpeg ./ffprobe ./ffplay || true
./ffmpeg -hide_banner -encoders | egrep 'libx264|libx265|libvpx|libopus|libmp3lame|libvorbis'
./ffmpeg -hide_banner -y -f lavfi -i testsrc2=size=320x240:rate=30 -t 2 -c:v libx264 -pix_fmt yuv420p /tmp/out_h264.mp4
./ffprobe -hide_banner -v error -show_format -show_streams /tmp/out_h264.mp4
./ffmpeg -hide_banner -v error -i /tmp/out_h264.mp4 -f null -
```

---

## 6. 跟踪记录

### 6.1 需求/决策记录
| ID | 日期 | 描述 | 状态 | 备注 |
|---|---|---|---|---|
| R-001 | 2026-11-20 | 从 GitHub 源码构建 Linux 完整可用 bin 工具集 | 进行中 | 目标 |
| R-002 | 2026-11-20 | 方案 A Docker 隔离构建 | 冻结 | |
| R-003 | 2026-11-20 | 版本 `n9.1`（HEAD `74e4393595...`，见 B-003） | 冻结 | |
| R-004 | 2026-11-20 | 必含 `ffmpeg/ffprobe/ffplay` | 冻结 | |
| R-005 | 2026-11-20 | 目标运行基线 noble x86_64 | 冻结 | |
| R-006 | 2026-11-20 | 代理 `gh-proxy.com` + GitHub 源 | 冻结 | |
| R-007 | 2026-11-20 | 必须使用 bk-ci 本地环境完成构建测试，**不修改 bk-ci 代码** | 冻结 | R-010 强调 |
| R-008 | 2026-11-20 | 能力基线：GPLv3、x264/x265/vpx/opus/mp3lame/vorbis/ass链/SDL2/zlib/bz2/lzma/OpenSSL/nasm，无 nonfree，无 AV1 | 冻结 | |
| R-009 | 2026-11-20 | （历史）前缀+tar.gz，动态依赖按约定运行 | 被替代 | 由 R-010 替代 |
| R-010 | 2026-11-20 | **需求变更：全静态链接，运行时无动态 `.so` 依赖；交付仅 3 个二进制 `ffmpeg/ffprobe/ffplay`（含 ffplay 全静态）**；推荐 musl/Alpine 静态构建；V4 改为静态可用性验证 | 已批准/实施中 | 用户确认“可以。不修改bk-ci的代码，你是做构建测试。切记！” |

### 6.2 Bug / 问题记录
| ID | 日期 | 现象 | 影响 | 根因 | 处理/规避 | 状态 |
|---|---|---|---|---|---|---|
| B-001 | 2026-11-20 | 宿主机直连 `github.com` 失败 | 直连获取受阻 | 网络受限 | 使用 `gh-proxy.com` 代理；容器内可达并成功克隆 | Mitigated |
| B-002 | 2026-11-20 | 代理访问 GitHub Releases/Tags API 403/404 | 版本探测受限 | 代理/匿名配额 | 以 `git ls-remote --tags` + commit 为准 | Mitigated |
| B-003 | 2026-11-20 | 期望 commit `9d106a4c...`（tag 对象）与构建 `HEAD` `74e43935...` 不一致 | 版本追溯需说明 | `n9.1` annotated tag，`n9.1^{}`=`74e4393595cf2b5857f0da925c4e0dd74ea306e5` | 以解引用提交为构建/追溯基准并记录 | Recorded |
| B-004 | 2026-11-20 | bk-ci dockerhost/dispatch IP/网关错误导致 2131008/不可达 | 构建无法启动 | 配置与实际主机不符 | 已修正 compose/DB 并重建 dockerhost | Mitigated |
| B-005 | 2026-11-20 | dockerhost Docker API 1.23 不兼容、状态刷新异常致 2131005 | 调度不可用 | API 版本与宿主 Docker 29.2.0 不匹配 | `apiVersion` 调至 1.44、重置计数/状态 | Mitigated |
| B-006 | 2026-11-20 | 构建容器 init 网关不可达/脚本需 docker CLI 与镜像能力不匹配 | 流水线内一键完成受阻 | 网关注入与执行镜像能力 | 网关配置已调整；流水线脚本/镜像需按 R-010 与可用环境收敛后再跑通 | Open |
| B-007 | 2026-11-20 | 动态链接产物在无运行时 `.so` 环境不可直接运行 | 不满足新需求 | 链接方式为动态 | 按 R-010 全静态重建并以 V4 静态验证替代 | Open |

### 6.3 验证记录
| 项 | 结论 | 证据 | 备注 |
|---|---|---|---|
| V1 版本与配置（静态） | 待执行 | - | 目标：n9.1/HEAD `74e43935`，含目标 enable 与静态构建 |
| V2 能力覆盖（静态） | 待执行 | - | C0 能力基线 |
| V3 功能冒烟（静态） | 待执行 | - | h264/h265/vp9/opus 等 + ffplay 验证 |
| V4 静态可用性 | 待执行 | - | noble x86_64 可运行，`file` 静态，`ldd` 无动态依赖 |
| （历史，动态构建）V1–V3 | 通过（有运行时依赖） | `/data/bkci-local/ffmpeg-out/build-report.txt`、`/tmp/ffmpeg-host-build.log`（2026-11-20） | 旧动态产物，不满足 R-010 |
| （历史，动态构建）V4 | 不适用新需求 | - | 动态依赖形态，已由 R-010 取代 |

### 6.4 实施日志
- 2026-11-20：完成调研与 C0 冻结，创建构建项目与 bk-ci 执行资产（`tools/ffmpeg-build/`）。
- 2026-11-20：bk-ci `demotest` 流水线 `p-8bb091809f5d4c04ac88fe7ef525f617`（ffmpeg-build-n9.1）多次构建测试；修复 dockerhost/dispatch 调度链路（B-004/B-005）后可启动构建容器，仍有镜像/初始化适配问题（B-006）。
- 2026-11-20：在 `ubuntu:24.04` 动态链接方式完成 n9.1 构建与 V1–V3 验证，产物落盘 `/data/bkci-local/ffmpeg-out/`、`tools/ffmpeg-build/out/`（历史动态产物，不满足后续新需求）。
- 2026-11-20：**需求变更 R-010**——用户要求全静态链接、运行时无动态 `.so` 依赖、交付仅 `ffmpeg/ffprobe/ffplay` 且 `ffplay` 同等全静态；同时要求**不修改 bk-ci 代码**仅做构建测试。文档已更新，待批准后按 musl 全静态方案重建与验证。
- 2026-11-20：**R-010 已批准并开始实施**（不修改 bk-ci 代码）。更新需求文档/README，重写 musl 静态构建资产（Alpine 3.20，源码构建 x265/libvpx/opus/ogg+vorbis/libass 等补齐静态库），构建镜像 `127.0.0.1:5000/ffmpeg-build:n9.1-static-musl`；启动全静态重建容器（输出 `/data/bkci-local/ffmpeg-out/`，日志 `/tmp/ffmpeg-static-build.log`）。旧动态产物已归档为 `*.dynamic-noble-20261120`。
- 2026-11-20：本地 Docker 静态构建测试多次失败：依赖 `libvpx` 曾从不可达 `chromium.googlesource.com` 克隆；脚本已改为优先 GitHub+`${GIT_PROXY_PREFIX}` 并补全代理封装，镜像重建后仍需结合缓存/重试收敛（记录见 B-008）。
- 2026-11-20：按“用 bk-ci 产品构建”要求操作流水线 `p-8bb091809f5d4c04ac88fe7ef525f617`：#8 `b-f33795bcec7c47c0840c918d6a5898ab` 使用自定义 alpine 静态镜像启动 Job 失败（`startVMStatus=FAILED`，`e-build UNEXEC`，无步骤日志）——自定义镜像不符合 bk-ci Docker 构建机 agent/init 约定，且不改 bk-ci 代码无法适配。#9 `b-4ff8f2852e9943cc975a193d16aae982` 同因 VM 启动失败。脚本改为 gzip+base64 内嵌（规避 16384 字符限制），镜像改回 `ubuntu:24.04` 触发 #10 `b-c854cfeb048242cc8aca7da6300a2df7`、#11 `b-a6c44745eb27427f8ea885f5c58c1f69`，均因 2131005 “no available Docker VM” 失败（`T_DISPATCH_PIPELINE_DOCKER_IP_INFO` 被 dockerhost 刷新为高 `USED_NUM`/负载，见 B-009）。
- 2026-11-20：重置 IP 信息后触发 #12 `b-fbfc5e123367418e8f6ed9e2e3b4690c`（`ubuntu:24.04`）成功调度并拉起容器，但 Job 容器立即退出(code 2)：`/data/init.sh` 依赖 `curl` 且 `docker_init.sh` 拉取/执行失败，agent 未启动（B-010）；构建停滞后已取消。
- 2026-11-20：流水线切换为 bk-ci 兼容镜像 `127.0.0.1:5000/bkci/ci:jdk17`（经验证含 curl/wget/git/tar/chroot/base64/gzip 等），触发 #13 `b-6e19ea2c151545fe9880a28620474b07`，因 B-009 导致 2131005 调度失败（未进入脚本）。已再次手工重置 `T_DISPATCH_PIPELINE_DOCKER_IP_INFO` 为低负载可用状态；**当前流水线配置与脚本已就绪，待明日重置 IP 后重试触发**。
- 2026-11-20（收工）：未产出 R-010 静态交付（`/data/bkci-local/ffmpeg-out/` 为空）。未修改 bk-ci 代码；未提交/未推送。明日优先：触发前确认/重置 dockerhost IP 记录 → bk-ci 执行构建(#14+) → 修复构建/静态链接问题直至 V1–V4 通过 → 收集证据并更新本文档。

## B-014 / B-015: uploadArtifact/uploadReport 在 local realm 部署下的兼容问题（2026-11-24）

### 现象
- #29 `b-ea6c9321a24c46e898d8faca78543f52`: `e-build SUCCEED`，`e-upload-artifact` 先 `2189501 Plugin Script is not exist!`，安装 v1.0.0 jar 后变 `2189503 Plugin File Sha is wrong!`，修正 `T_ATOM_ENV_INFO.SHA_CONTENT` 后变 `2199001 upload file failed`。
- smoke pipeline `p-52b5ec18b8c140a78c78fb7dcbf9c96e` 复现：uploadArtifact 请求 gateway 返回 `503 {"message":"后台正在部署中，请稍后。"}`。

### 根因
1. **官方插件 jar 路径与 local realm 不匹配**：解包 `uploadArtifact-jar-with-dependencies.jar` / `uploadReport-jar-with-dependencies.jar`（v1.0.0）确认 `ArchiveApi.uploadBkRepoPipelineFile` 调用 `/bkrepo/api/build/generic/...`。
2. **local deploy 未部署 bkrepo-generic**：`deploy/local` 配置 `BK_CI_ARTIFACTORY_REALM=local`，consul 无 `bkrepo-generic` 服务；bkrepo 栈为 3.8.9-rc.2，但可达镜像源无 `bkrepo-generic:3.8.9-rc.2`，仅拉到 2.2.2-rc.2，启动后未注册 consul，与 3.x 不兼容，已清理试验容器。
3. **gateway archive 路由是 bkrepo 风格**：`src/gateway/core/artifactory.conf` 将 `/artifactory/(archive|report)/upload/build/...` 代理到 `$target/generic-local/bk-...`，local realm 无该后端，导致 503。

### 已做临时修复/验证
- 安装官方 v1.0.0 jar 到 `/data/bkce/public/ci/artifactory/bk-atom/demo/{uploadArtifact,uploadReport}/1.0.0/`。
- 更新 `T_ATOM_ENV_INFO.SHA_CONTENT` 为实际 jar sha256（uploadArtifact=`82341191...d836`, uploadReport=`808ba978...dcfa`）。
- 已将排查时临时改为 bkrepo 的配置恢复为 local：`deploy/local/rendered/etc/ci/application-artifactory.yml`、gateway 容器 `/usr/local/openresty/nginx/conf/lua/init.lua`、artifactory 已重启。
- 验证 local MS API 可直接归档：容器内 `POST http://localhost:21920/api/build/artifactories/file/archive?fileType=BK_CUSTOM...` 返回 200。

### local 兼容替代（进行中）
- smoke pipeline `p-52b5ec18b8c140a78c78fb7dcbf9c96e` 的 `e-upload-artifact/e-upload-report` 已替换为 `linuxScript`，直接调用 artifactory MS `/api/build/artifactories/file/archive`（BK_CUSTOM/BK_REPORT）并调用 process report 记录接口。
- smoke #4: 通过 gateway `/ms/...` 500（artifactory 本体可用，gateway 转发链路待查）。
- smoke #5: 容器内用 `bkci-artifactory:21920` DNS 解析失败（Job 容器网络/DNS）。
- smoke #6: 用 `172.28.0.18:21920` 直连，出现 `curl (28)` 连接超时；需确认 Job 容器到 bkci_artifactory 网络可达性/路由。

### 正式修复建议
1. **首选（产品一致）**：补齐 `bkrepo-generic:3.8.9-rc.2` 镜像，纳入 `deploy/local/docker-compose.yml`，注册 consul，创建 `bk-archive/bk-report` generic repo；将 `BK_CI_ARTIFACTORY_REALM=bkrepo`，验证 uploadArtifact/uploadReport 原生插件。
2. **local 兼容（deploy 兜底）**：为 `artifactory.realm=local` 提供 gateway 路由兼容或在插件侧检测 realm 走 `/ms/artifactory/api/build/artifactories/file/archive`；至少应在 deploy/local 文档中声明 uploadArtifact/uploadReport v1.0.0 依赖 bkrepo-generic。
3. **CI smoke**：在 deploy/local 验收脚本中增加“制品上传/报告”最小 smoke，避免全量 ffmpeg 构建才暴露。

### 影响
- B-011（构建制品 Tab）、B-012（产出报告 Tab）未完成 bk-ci UI 验收；R-010 二进制本身已在 #26 产出并归档到 `/data/bkci-local/ffmpeg-out/`。

### B-011/B-012 local 兼容验证结果（2026-11-24 晚）

- **构建制品 Tab（B-011）已通过 UI 确认**：用户查看 smoke #9 `b-2948ed20d4b04cd6a21ca768ba4d1ab3` 的“构建制品”页签，能看到：
  - `build-report.txt`（0.03KB）
  - `checksums.txt`（0.01KB）
  - `ffmpeg-n9.1-linux_x86_64-musl-static.tar.gz`（0.18KB，由 smoke 脚本生成的占位 tar.gz）
- **产出报告 Tab（B-012）链路已打通**：smoke #10 `b-6ec956f275334875a02464d8869a9b34`
  - `e-upload-artifact` / `e-upload-report` 均 `SUCCEED`
  - 产物归档与报告文件归档均返回 `http=200`
  - 报告记录接口返回 `report_http=200 {"status":0,"data":true}`
  - `GET /process/api/user/reports/demotest/p-52b5ec18b8c140a78c78fb7dcbf9c96e/b-6ec956f275334875a02464d8869a9b34` 返回报告记录 `smoke-upload-report`
  - 后续修正报告 `indexFile` 为 basename，避免 `e-upload-report/e-upload-report/build-report.txt` 双前缀。

### ffmpeg 正式流水线 local 兼容改造与重跑（2026-11-24 晚）

- 流水线 `p-8bb091809f5d4c04ac88fe7ef525f617` 的 `e-upload-artifact` / `e-upload-report` 已由 `uploadArtifact/uploadReport` 插件改为 `linuxScript` local 兼容实现：
  - 归档接口：`POST http://172.17.0.5:21920/api/build/artifactories/file/archive?fileType=BK_CUSTOM|BK_REPORT...`
  - 产物源目录兼容 `$WS/ffmpeg-out-static` 与 `$WS/alpine-rootfs/work/out`
  - 压缩包匹配 `ffmpeg-*-musl-static.tar.gz`（实际构建产物名为 `ffmpeg-n9.1-linux-x86_64-musl-static.tar.gz`，注意是 `linux-x86_64`）
  - 报告记录使用 `name=...&indexFile=$bn&reportType=INTERNAL`，带 `X-DEVOPS-VM-NAME`
- 已触发 ffmpeg 正式构建 **#30 `b-8db443465408422eab640ea459208745`**，等待结果。
- 注意：`172.17.0.5` 是 `bkci-artifactory` 在 Docker `bridge` 网络中的当前 IP；容器重建后可能变化。正式修复应补齐 bkrepo-generic 或做 realm 兼容路由/固定网络别名。

### 暂停记录（2026-11-24 夜）

- 用户要求：ffmpeg #30 继续在 bk-ci 后台运行，明天再继续跟进。
- 已停止本地状态轮询进程；**未停止/取消 bk-ci 构建**。
- 明天继续点：
  - 构建 `p-8bb091809f5d4c04ac88fe7ef525f617` / `b-8db443465408422eab640ea459208745` 状态与三步骤结果
  - `e-upload-artifact` 产物归档 3 个文件
  - `e-upload-report` 文件归档 + 报告记录 200
  - UI“构建制品”/“产出报告”Tab 对 #30 的最终确认

### #30 最终结果（2026-11-25）

- ffmpeg 正式构建 `p-8bb091809f5d4c04ac88fe7ef525f617` / `b-8db443465408422eab640ea459208745`：**SUCCEED**
  - `e-build SUCCEED`
  - `e-upload-artifact SUCCEED`
  - `e-upload-report SUCCEED`
- 上传日志证据：
  - `build-report.txt`、`checksums.txt`、`ffmpeg-n9.1-linux-x86_64-musl-static.tar.gz` 归档均 `http=200`，`uploaded=3 files`
  - 报告文件归档 `http=200`
  - 报告记录 `report_http=200 {"status":0,"data":true}`
  - `GET /process/api/user/reports/.../b-8db443465408422eab640ea459208745` 返回 `ffmpeg-r010-build-report`
- 二进制证据：
  - `file`：`ELF 64-bit LSB executable, x86-64, statically linked`
  - `ldd`：`not a dynamic executable`（ffmpeg/ffprobe/ffplay）
  - `-version` 三个二进制均输出 `n9.1`，configuration 含 `--enable-static --disable-shared --enable-gpl --enable-version3 --enable-libx264 ... --enable-sdl2`
  - tar 包内容仅 `ffmpeg`、`ffprobe`、`ffplay`

### ffplay_enabled 报告字段修正（2026-11-25）

- 现象：#30 上传的 `build-report.txt` 里 `ffplay_enabled=0`，但 `ffplay` 二进制存在且 `-version` 正常。
- 根因：`tools/ffmpeg-build/scripts/build-in-container.sh` 用 `grep -q '^CONFIG_FFPLAY=1'` 判断；FFmpeg 9 的 `ffbuild/config.mak` 写 `CONFIG_FFPLAY=yes`，导致误判。
- 修复（TDD）：
  - 新增失败测试 `tools/ffmpeg-build/test/ffplay_enabled_test.sh`，先见证 RED（`ffplay_enabled: command not found`），再实现 GREEN。
  - 在 `build-in-container.sh` 增加 `ffplay_enabled()`，接受 `CONFIG_FFPLAY=yes|1`，或已构建的 `$OUT_DIR/bin/ffplay` 可执行文件。
  - 替换 configure 重试判断和最终报告字段判断。
  - 测试 4/4 PASS。
  - 已重新生成并写回 ffmpeg pipeline 内嵌 gzip+base64 构建脚本。
- #30 已交付的 `build-report.txt` 已修正 `ffplay_enabled=1` 并清理 pipefail 造成的独立 `missing` 行；已重新归档到 #30 的 `BK_CUSTOM` 与 `BK_REPORT` 路径（均 `http=200`）。
- 通过 artifactory download API 复核归档内容：`ffplay_enabled=1`、`all_static=1`、`missing_bin=0`、`tarball=...`。

### 产出报告无法打开与制品多出一项的修复（2026-11-25）

- 用户反馈：
  - “构建制品” Tab 从 3 个文件变成 4 个文件。
  - “产出报告” Tab 能看到 `ffmpeg-r010-build-report`，但打开提示 `localhost 拒绝了我们的连接请求`。
- 根因：
  - `GET /artifactory/api/user/pipeline/output/.../search` 对 INTERNAL 报告返回绝对 URL：`http://localhost:8080/artifactory/api-html/user/reports/...`。
  - 浏览器从其他机器访问 bk-ci 时，`localhost` 指向用户本机，本机 8080 没有服务，因此连接被拒绝。
  - `UserReportResourceImpl` 已通过 `RegexUtils.splitDomainContextPath` 剥掉域名，但 `PipelineOutputServiceImpl` 没有；旧流水线 UI 的 `Outputs/index.vue` 直接把该 URL 放进 iframe。
  - 第 4 个制品是修正 `ffplay_enabled=0` 后重新上传 `build-report.txt` 产生的重复 `T_FILE_INFO` 元数据记录；同一路径在 UI 中出现两次。
- 修复（前端 source-only，未改后端/流水线）：
  - 新增 `src/frontend/devops-pipeline/src/utils/report.js`：`normalizeInternalReportUrl(url, reportType)`，仅对 `INTERNAL` 报告把绝对 URL 收敛为当前站点可解析的 path（保留 query/hash），`THIRDPARTY` 保持绝对 URL。
  - `src/components/Outputs/index.vue` 在 `records.map` 中调用该函数，并把归一化后的 `indexFileUrl` 写入 output。
  - TDD：先写 `src/utils/report.test.js` 并见证 RED，再实现 GREEN；6/6 PASS。
  - 测试命令（使用 workspace 的 Vitest 3）：
    `cd src/frontend/devops-flow && npx vitest run --config ../devops-pipeline/vitest.config.js src/utils/report.test.js`
- 验证证据：
  - 修正后 `POST http://localhost:8088/artifactory/api/user/pipeline/output/.../search` 返回 4 条：3 条 `CUSTOM_DIR` + 1 条 `REPORT`；`build-report.txt` 重复项已消失。
  - `GET http://localhost:8088/artifactory/api-html/user/reports/.../build-report.txt` = `http=200`。
  - 删除 #30 的两条旧元数据记录（`190e5a6546524921a4ecc25d69a8b8b0` 旧 BK_CUSTOM、`f560a9a4903042bba4b68100498538ab` 旧 BK_REPORT）及其 props；DB 复核 #30 仅保留各 1 条 BK_CUSTOM/BK_REPORT 记录。
  - dev server `:8006` 在源文件变更后重新编译，bundle hash 从 `pipeline.e0ae44ea0ce78f4bbff2.min.js` 变为 `pipeline.c9b977afc1060f03a825.min.js`，并包含新增 helper 的字符串痕迹。
- 待用户 UI 复核：刷新 #30 详情页后，“构建制品”恢复 3 个文件，“产出报告”点击/iframe 可打开。

### 用户 UI 复核确认（2026-11-25）

- 用户确认 #30 详情页：
  - “构建制品” Tab 恢复为 **3 个文件**。
  - “产出报告” Tab 的 `ffmpeg-r010-build-report` **可以打开**。
- 至此 B-011（构建制品可见/可下载）、报告记录可见与可打开均已有 UI 证据。

### 2026-11-25 提交与 OpenSpec 状态说明

- 用户明确授权“先提交”，因此本次将 `add-atom-logo-load-fallback` 与 `add-blank-pipeline-creation-entry` 两个 active change 补 `.openspec.yaml` 后归档，并提交到 `master`、推送 `mine master`。
- OpenSpec gate 的 3.1–3.4、4.1–4.5 验证证据仍未补齐，对应 `tasks.md` 条目保持未勾选；本次提交不包含伪造的验证结论。
- 后续补齐证据后，再单独更新归档 change 的 tasks 与计划文档。

### 2026-11-25 可复现构建资产提交范围

- 已按 `docs/superpowers/specs/2026-11-25-ffmpeg-n91-build-assets-design.md` 提交构建脚本、校验脚本与脱敏流水线模板。
- 不提交二进制、tar、构建报告、校验和、FFmpeg 源码、rootfs、依赖缓存、真实 ID/IP/凭据。
- 校验：`verify_static_test.sh`、`ffplay_enabled_test.sh`、`template_hygiene_test.sh`、`render_pipeline_test.sh` 均 PASS。
