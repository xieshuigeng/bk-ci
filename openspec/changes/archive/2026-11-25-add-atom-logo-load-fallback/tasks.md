## 1. 统一图标单元

- [x] 1.1 在 `bk-pipeline` 新增 `AtomLogo.vue`：入参 `logoUrl`、`name`（sprite 图标名）、`size`、`cls`；内部优先远端图，`@error` 后置 `failed` 并渲染 `Logo :name`。（`cls` 依赖 Vue 属性透传落到 root `img`/`Logo`，与宿主既有样式类直挂等价）
- [x] 1.2 加载中/失败态使用与现 `logoCls` 同尺寸占位，禁止浏览器默认裂图标记外露。
- [x] 1.3 失败态按 `logoUrl` 维度缓存在模块级 `Set`（会话内有效），使同 URL 的其余元素直接走回退、不再发请求。
- [x] 1.4 导出该单元（`bk-pipeline/index.js`），供宿主 `devops-pipeline` 复用。

## 2. 调用点替换

- [x] 2.1 `bk-pipeline/src/Atom.vue:38-39` 的 `<img>/<Logo>` 二选一改为 `AtomLogo`，保留 `atom.asyncStatus`/状态图标等前置分支顺序不变。
- [x] 2.2 `devops-pipeline` 调用点替换：`components/AtomSelector/atomCard.vue:9`、`AtomSelector/imageCard.vue:10`、`AtomSelector/honer-img.vue:6`、`views/CreatePipeline.vue:172`、`views/AtomManage.vue:42`、`components/Template/Install/StoreTemplateList.vue:31`。（atomCard 的远端图经 `honer-img` 渲染，其内部已换为 `AtomLogo`，保留 `v-if="atom.logoUrl"` + 荣誉角标语义，不直接平替）
- [x] 2.3 逐点确认原有 `v-if="xxx.logoUrl"` 的显隐语义：原本"无 logo 则不渲染图片节点"的位置改为 `AtomLogo`（其内部处理空 URL → sprite/兜底），避免布局塌陷。

## 3. 回归与验证

- [ ] 3.1 组件级：`logoUrl` 返回 200 时渲染结果与改动前一致（截图/快照比对）。
- [ ] 3.2 组件级：`logoUrl` 返回 500/404 时渲染内置 sprite 图标，无浏览器裂图，且控制台无重复请求（同 URL 仅一次）。
- [ ] 3.3 组件级：sprite 无同名图标时落到既有兜底 `#bk-pipeline-order`。
- [ ] 3.4 画布级：本地部署复现场景（`logoUrl` 未初始化）下，画布各阶段元素仍有图标；执行历史、原子选择器、插件管理页同样成立。
- [x] 3.5 `bk-pipeline` 库构建（`pnpm --filter bkui-pipeline run build`，含 vue2 产物）与前端 lint/typecheck 通过。（vue2/vue3 产物均含 `AtomLogo` 导出；devops 侧改动文件 eslint 通过；bk-pipeline 目录 `.vue` 的 eslint 因 `bk-pipeline/.eslintrc.js` 与 eslint@7/8 混装既有损坏，未改动前亦复现）

## 验证状态（2026-11-19）

3.1–3.4 **未勾选**：本轮只做文档对账；且前端镜像来自 release 产物、不含 `AtomLogo`，当前部署未重建镜像。验证前置：新机按 `/home/xsg/aicode/bkci-local-stash/README.md` 恢复后，在 `src/frontend/devops-pipeline` 执行 `npm run dev`（`:8006`）+ 反代 `:8088`，浏览器访问 `http://<host>:8088/console/`。

逐条验证口径：
- 3.1 让 `logoUrl` 返回 200（内置图标经网关可达的原子），对比改动前后截图/DOM：仍为 `<img>`，尺寸与类名一致。
- 3.2 用本地环境确实 500 的 `codeTapdWebHookTrigger`（`tapdTrigger.png`）作负例：应显示 sprite 图标而非裂图；浏览器 Network 面板确认同一 URL 只请求一次（模块级 `Set` 缓存生效）。
- 3.3 构造 sprite 中不存在的 `name`，应落到 `#bk-pipeline-order` 兜底图标。
- 3.4 本地部署 `demo` 项目下查看画布、执行历史、原子选择器、插件管理页，确认图标均可见；记录截图路径。

结果写入本节并同步到 `docs/superpowers/plans/2026-10-20-bkci-local-docker-deploy.md` 新增的 `### 2026-11-19 openspec 验证` 续节。四项全通过后才允许勾选并归档。

### 2026-11-25 提交说明

- 用户明确授权“先提交”：本 change 随 FFmpeg n9.1 验证修复一起归档并提交到 `master`。
- 3.1–3.4 的截图/Network/DOM 证据尚未补齐，故仍保留未勾选状态；后续补证据后再单独更新，不在本次提交中伪造验证结论。
