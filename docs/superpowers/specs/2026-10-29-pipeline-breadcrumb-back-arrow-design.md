# 流水线详情页面包屑返回箭头设计（最小修复）

- 日期：2026-10-29
- 范围：`src/frontend/devops-pipeline/src/components/PipelineHeader/`
- 状态：已确认（分节评审通过）

## 背景与根因

bk-breadcrumb 组件的 `back-router` prop 与 `#prefix` 插槽互斥：`prefix` 插槽存在时不渲染返回箭头。`PipelineBreadCrumb.vue` 无条件渲染 `#prefix`（流水线 logo），导致所有使用页传入的 `back-router` 均失效，流水线执行详情页缺少返回入口。

## 目标

- 需要返回入口的页面显式开启后，显示 bk-breadcrumb 内建返回箭头；箭头目标可由 `backRoute` prop 覆写，缺省返回流水线列表页（`PipelineManageList`）。执行详情页覆写为本流水线的执行历史页（`pipelinesHistory`，即构建列表）。
- 未开启的页面渲染结果与改动前完全一致。

## 非目标

- 不改路由表与面包屑层级生成逻辑（`breadCrumbs` 计算不动）。
- 不做其他视觉调整；不批量为其余页面开启返回入口。
- 不修改 bk-ui 组件本身。

## 方案

新增 `showBack: Boolean` prop（缺省 `false`），控制互斥取舍：

| showBack | `#prefix` 插槽 | back-router | 呈现 |
|---|---|---|---|
| `false`（默认） | 渲染（logo） | 传 `null` | 与现状一致：logo 前缀、无箭头 |
| `true` | 跳过 | 传 `backRoute \|\| manageRoute` | 内建返回箭头替换 logo，目标为覆写路由（缺省列表页） |

箭头样式采用 bk-breadcrumb 内建，不做覆盖。

### 层级语义（2026-10-29 浏览器验收后修订）

验收发现：详情页的上一级应是**构建列表（执行历史页）**而非流水线列表页——面包屑「流水线」级已负责回列表，箭头再指列表属重复且跳级。故新增 `backRoute: Object` prop 覆写箭头目标，执行详情页传入 `pipelinesHistory`（params 仅 `projectId`+`pipelineId`，`type`/`version` 省略由路由 `beforeEnter` 补默认）。箭头与面包屑一级各司其职：箭头=上一级（构建列表），面包屑「流水线」=回列表。

## 改动清单

1. `PipelineBreadCrumb.vue`
   - 新增 `showBack` prop（注释说明互斥根因）与 `backRoute: Object` prop（箭头目标覆写）；
   - `:back-router="showBack ? (backRoute || manageRoute) : null"`；
   - `#prefix` 插槽加 `v-if="!showBack"`。
2. `DetailHeader.vue`
   - 使用处加 `show-back` 与 `:back-route="historyRoute"`（computed：`{ name: 'pipelinesHistory', params: { projectId, pipelineId } }`）。

其余消费页（EditHeader、HistoryHeader、PreviewHeader、DraftDebugHeader、ImportPipelineHeader）不动；后续页面需要返回入口时加一个 `show-back` 属性即可。

## 验证与验收

1. 静态：devops-pipeline 目录下用项目自带 eslint 检查改动两文件（`npx eslint`，仓库无 lint npm 脚本）。
2. 渲染：`npm run dev` 起 webpack dev server 快查（不做整包 `public` 生产构建）。
3. 手工验收（本地 docker 部署环境）：
   - 执行详情页出现返回箭头，点击回到本流水线的执行历史页（URL 形如 `.../<pipelineId>/history/history`）；
   - 编辑页 / 执行记录页 / 预览页仍为 logo 前缀、无箭头，与改前一致。

## 回滚

两文件小 diff，`git checkout` 即完全回滚；无数据、接口影响。
