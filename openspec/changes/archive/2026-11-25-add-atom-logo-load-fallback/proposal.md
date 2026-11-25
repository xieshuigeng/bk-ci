## Why

画布元素与各类卡片在原子 `logoUrl` 加载失败时直接表现为"无图标"，没有任何回退或占位。渲染链是：`src/frontend/bk-pipeline/src/Atom.vue:38-39` —— `logoUrl` 非空即无条件渲染 `<img>`，只有 `logoUrl` 为空时才走 `<Logo v-else :name="svgAtomIcon">` 的内置 sprite 图标：

```vue
<img v-else-if="atom.logoUrl" :src="atom.logoUrl" :class="logoCls" />
<Logo v-else :class="logoCls" :name="svgAtomName" size="18" />
```

因此只要图标文件缺失（社区/私有化部署很常见：官方发布流程上传的 `file/$<hash>.<hash>.png` 与 SaaS 专属的 `tapdTrigger.png`、`scmGitTrigger.png` 在本地环境均返回 500），用户看到的就是空白，并被误判为前端渲染 bug 或编码问题（本地部署即因此走了一轮排查，见 `deploy/local/README.md` 排障节）。同一"无条件 `<img>`"模式还复制在 `devops-pipeline` 的多处：`components/AtomSelector/atomCard.vue:9`、`AtomSelector/imageCard.vue:10`、`AtomSelector/honer-img.vue:6`、`views/CreatePipeline.vue:172`、`views/AtomManage.vue:42`、`components/Template/Install/StoreTemplateList.vue:31`。

## What Changes

- `bk-pipeline` 的原子图标改为统一的图标加载单元（建议新增 `AtomLogo.vue` 或在 `Logo.vue` 之上包一层）：优先远端 `logoUrl`，**加载失败（`@error`）时回退内置 sprite 图标**（沿用现 `svgAtomIcon` 名称推导），失败态按 `atomCode` 缓存，避免同类元素反复请求失败资源。
- 远端图标加载中给出既有尺寸占位，避免宽度跳变；不使用浏览器默认裂图图标。
- `bk-pipeline` 内置 sprite 缺对应图标时保持现兜底（`Logo.vue:38-44` 的 `#bk-pipeline-order` 兜底），不改动。
- `devops-pipeline` 上述同类调用点改用同一单元，行为统一（模板/插件市场卡片同样回退到现有兜底图）。
- 不改动后端元数据与 `logoUrl` 生成规则；不新增网络请求（仍是一次 `logoUrl` 请求，失败后不再重试）。

## Capabilities

### New Capabilities
- `atom-logo-fallback`: 原子/模板远端图标加载失败时回退内置 sprite 图标，保证画布与卡片始终有可辨识图标。

### Modified Capabilities
- 无（图标正常可用时渲染结果与现状一致）

## Impact

- 影响模块：`src/frontend/bk-pipeline`（新增图标单元，`Atom.vue` 等调用点）、`src/frontend/devops-pipeline`（原子选择器、插件管理、新建流水线模板列表、模板安装列表等调用点替换）。
- 影响 API 与数据：无。
- 影响性能：减少同类失败请求（失败态缓存）；每张图标仍最多一次网络请求。
- 影响可测性：图标回退可在组件层用"远端 500"固定桩件测试（当前无可用 seam，`Atom.vue` 直接内联 `<img>`）。
- 验证要点：① `logoUrl` 200 → 与改动前一致；② `logoUrl` 500/404 → 显示 sprite 同名图标，无浏览器裂图；③ sprite 亦无同名图标 → 显示既有兜底图标；④ 同一 `atomCode` 多元素只触发一次失败请求。
