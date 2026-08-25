# MachineContext 产品方向

## 1. 定位

MachineContext 是一个私有、可验证、AI 可快速读取的本机上下文层。它把“这台电脑现在是什么状态”整理为稳定、轻量、可维护的事实，让网页端 ChatGPT、本地 Codex/Agy 以及未来其他 Agent 在规划软件安装、开发环境、项目工作、更新迁移和排障时，不必反复向用户询问版本、路径、已有工具和环境关系。

它首先是一个 **文件仓库 + 本地维护工具**，而不是传统桌面软件。

## 2. 核心问题

网页 AI 无法直接看到本机，因此经常出现额外往返：先给方案 -> 用户本地查版本/路径/依赖 -> 再反馈 -> AI 重做方案。聊天记忆可能陈旧，用户自己也不可能完整记住所有工具和项目。

MachineContext 不仅要保存“已知信息”，还要通过结构化系统来源、目标探测和可选 indexed discovery 主动发现用户忘记的环境事实，再经过验证后发布为统一 machine truth。

## 3. 产品原则

项目最重要的属性是：

1. **可维护**：信息必须容易重新检测、验证和更新，不能依赖长期手工记忆。
2. **便捷迅速**：AI 通常先读一个短入口，需要时再按模块深入；日常 Quick scan 不应被深度 discovery 拖慢。
3. **完整详细**：保留足以支持安装、开发、迁移和排障决策的事实及关系，并具备发现未知项的机制。
4. **实时可信**：易变化的信息有明确来源/验证状态；partial/failed scan 不能伪装成完整 truth。
5. **轻便简洁**：不做企业 CMDB，不复制已有 project manifest，不积累无意义 raw scan 数据。
6. **可扩展**：未来增加软件类别、provider、项目、多环境或交互方式时，应主要通过新增模块完成，而不是推翻 identity/目录/数据模型。

## 4. V1 用户体验

对网页端或本地 AI：

`CURRENT.md -> machine-context.json -> 按需读取 context/*.json`

对本机维护：

`collect/discover -> reconcile/verify -> privacy/validation -> render -> atomic publish -> review diff -> commit/push`

扫描模式：

- Quick：日常快速重新验证；
- Discover：主动找遗漏/未知候选；
- Enrich：只对选中对象做昂贵详情检查；
- Full：第一次建库或深度审计。

理想情况下用户不需要记住大量维护步骤，后续可以收敛为 `mc sync` / `mc scan` 等少量入口。

## 5. V1 范围

第一阶段优先覆盖：

- Windows、硬件、磁盘、Shell、关键 PATH 与目录；
- 开发 runtime、版本管理器、包管理器、SDK、编译器、CLI 和开发工具；
- AI coding / harness / bridge 工具；
- 与开发决策相关的网络、代理、本地服务与端口；
- structured installed-app metadata 与 portable/custom-install candidate discovery；
- 本机长期开发项目及其环境级依赖；
- 软件安装位置、安装方式、更新方式和目录使用习惯；
- 对规划和排障有价值的跨工具/项目关系；
- 隐私安全、provider health、验证和过期/缺失语义。

## 6. 明确不做

V1 不做：

- 企业式完整 Windows CMDB；
- 无边界全盘递归读取；
- 所有进程、网络连接、注册表、历史或文件内容的 raw dump；
- secrets/凭据管理；
- 复制 project lockfile 或完整 dependency graph；
- 为了“像产品”提前引入数据库、服务端或复杂 GUI；
- 为了扫描自动安装依赖/Everything/osquery；
- 自动修改系统环境以迎合清单；
- 把 WSL/container/project-local runtime 扁平混成 Windows host 状态。

## 7. 后续设想

以下方向保留，但只有真实使用证明有价值后才实现：

- **非开发软件上下文**：浏览器、设计/创意、生产力、媒体、常用工具等，以新 software module 加入；
- **轻量 CLI**：`mc scan`、`mc status`、`mc sync`、`mc project add`；
- **更好的变化/影响分析**：提示 path/update/manager/relationship 变化的 downstream impact；
- **安装建议辅助**：根据磁盘用途、既有目录规范、update channel 和 downstream dependency 判断安装位置/方式；
- **read-only MCP**：本地 Agent 高频查询 live/canonical context 时作为可选 access surface；
- **多环境/多机器**：只有出现真实第二设备或深度 WSL/container 需求时增加 scope/profile；
- **本地 Dashboard**：只有文本/CLI 已无法满足浏览和维护效率时考虑。

无论未来增加 CLI、MCP 或 UI，可读、可迁移、可审计的 canonical files 都保持核心数据层。
