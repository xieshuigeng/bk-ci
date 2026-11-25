## Why

新建流水线页面强制要求先选中一个"已安装模板"才能提交（`src/frontend/devops-pipeline/src/views/CreatePipeline.vue:368-369`：`isConfirmDisable = isDisabled || !activeTemp?.installed || isActiveTempEmpty`），页面上没有独立的"空白创建"入口，模板只有"项目自定义"和"模板商店"两个面板（同文件 `:336-340`、`:382-399`）。

私有化/离线部署里两个面板常常同时为空。本地 Docker Compose 部署实测：

```bash
GET /process/api/user/pipeline/template/v2/<project>/allTemplates   → {"status":2101034,"message":"流水线: 模板不存在"}
GET /store/api/user/market/template/list?page=1&pageSize=20         → {"status":0,"data":{"count":0,"records":[]}}
```

结果是：普通用户在该部署里**无法通过 UI 新建任何流水线**，只能走"导入"或直接调用 `POST /process/api/user/pipelines/{projectId}`（该接口接收流水线 `Model`，本身就支持空白创建，已在本地验证可用）。能力在服务端已具备，缺的只是入口，属于纯前端可闭环的可用性缺口。

注：`src/frontend/locale/flow/zh-CN.json` 里"从空白开始，或从模板创建/空白模板"属 `flow.content.*`（创作流产品），全 `src/frontend` 无引用、部署产物内亦不存在，因此不作为本提案的实现依托。

## What Changes

- 流水线列表"新建流水线"入口新增**空白创建**通路：无模板也可直接创建一条仅含空阶段结构的流水线，创建后直接进入编排页。
- 新建流水线页面在模板面板为空（项目模板与模板商店均无可用项）时：隐藏模板选择区与"复制模板配置"项，创建按钮仅按流水线名称与权限校验；面板非空时现有交互（单选模板 + 自由/约束模式）保持不变。
- 模板为空时给出可见引导：说明当前无可用模板，并提供"空白创建"和"导入"两个动作，避免按钮静默禁用。
- 创建请求沿用既有接口：空白创建走 `POST /process/api/user/pipelines/{projectId}`（body 为 `Model`），不新增后端接口、不改变模板创建路径 `createPipelineWithTemplate` 的行为。
- 新增文案入 `src/frontend/locale/pipeline/`（`zh-CN`/`en-US`），不复用 `flow.content.*`。
- 权限沿用项目级"新建流水线"（`RESOURCE_ACTION.CREATE`），不引入新权限位。

## Capabilities

### New Capabilities
- `pipeline-blank-creation`: 在无可用模板的情况下，通过 UI 空白创建流水线并能进入编排页继续编辑。

### Modified Capabilities
- 无（模板创建/导入路径行为不变）

## Impact

- 影响模块：前端 `devops-pipeline`（`views/CreatePipeline.vue`、流水线列表新建入口、`store/modules/common/pipeline.js` 的模板拉取容错）与 `locale/pipeline/*`。
- 影响 API：无新增；空白创建复用 `POST /process/api/user/pipelines/{projectId}`。
- 影响数据与状态：无 DB 变更；不写入模板相关字段（`emptyTemplate`/`instanceType` 仅在模板创建路径继续使用）。
- 影响兼容性：已有"选模板创建"与"导入"流程行为与入参不变；`allTemplates` 返回 `2101034` 时前端按"无模板"处理而非报错。
- 验证要点：① 模板商店与项目模板皆空 → 可空白创建并进入编排页；② 存在已安装模板 → 原选择流程无回归；③ 无 CREATE 权限 → 入口禁用且提示不变。
