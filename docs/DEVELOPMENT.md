# MachineContext 开发计划

## 当前阶段

当前处于 **V1 Bootstrap / Initial Audit**。目标不是继续讨论目录，而是让本地 Agent 打开 `E:\MachineContext` 后可以直接开始实现一条可靠的最小维护链，并用真实机器完成第一次只读审计。

## V1 交付目标

V1 完成时应满足：

1. 能安全、只读地采集 `docs/COLLECTION_SPEC.md` 中 V1 必需的机器事实；
2. 能把检测结果写入 `context/` 下的 canonical YAML，而不是只生成一次性报告；
3. 已有记录能够重新验证，并区分 `verified / stale / pending / unavailable`；
4. `CURRENT.md` 可由 canonical 数据生成，保持短且适合 AI 快速读取；
5. push 前有隐私检查，禁止 secrets 和未经允许的原始 dump 进入仓库；
6. 同步流程尽量只产生必要 diff，不因为排序/格式造成大面积噪声；
7. 能登记本机长期项目，但只保存环境级上下文，不复制项目自己的完整依赖树；
8. 初次审计后能够形成真实的安装/更新目录习惯，而不是根据聊天记忆硬编码规则。

## 推荐实现顺序

### Phase A — Read-only collector

先实现 PowerShell 采集层。按领域拆 collector，不要写一个巨大的脚本：

- system / hardware / storage;
- shells / PATH / command resolution;
- runtimes / package managers;
- SDK / compiler / developer tools;
- AI tools;
- network / proxy / approved local services;
- project discovery（只发现候选，不自动把所有目录认定为项目）。

采集必须 fail-soft：某个工具不存在或某条检测失败，不应导致整个扫描失败。

### Phase B — Normalize and verify

把不同来源规范为稳定 ID 和字段；检测到的客观事实与手工/语义字段分开处理。支持重新验证、过期和不可用状态。

### Phase C — Render and validate

实现：

- `render.ps1`：由 canonical context 生成 `CURRENT.md`；
- `validate.ps1`：检查结构、引用、重复 ID、危险内容和明显 secrets；
- 稳定输出顺序，避免无意义 diff。

### Phase D — Sync entry point

实现一个简单 `sync.ps1` 串起：

`collect -> verify -> validate/privacy -> render -> git diff`

V1 默认不要未经用户/Agent review 自动 push。先把可靠性做好，再决定是否增加 `-Push` 或 CLI 封装。

### Phase E — Initial real-machine audit

在真实机器上运行并人工/Agent 复核：

- 旧聊天线索只能用于“应该去哪里查”，不能直接进入 canonical truth；
- 对工具角色（primary / legacy / testing 等）做语义确认；
- 对安装目录现状做归纳，形成 `context/conventions.yaml`；
- 登记真正需要长期维护的项目；
- 检查生成后的 `CURRENT.md` 是否足以支持网页 GPT 快速规划。

## 代码组织建议

```text
scripts/
  collect.ps1
  verify.ps1
  render.ps1
  validate.ps1
  sync.ps1
  collectors/
  lib/

tests/
  fixtures/

context/
  machine.yaml
  network.yaml
  conventions.yaml
  relationships.yaml
  software/
  projects/
```

不要为 V1 引入数据库或常驻后台服务。PowerShell 足以覆盖 Windows 初始采集；如果后续复杂度确实超过脚本能力，再评估更适合的实现语言或 CLI。

## 关键工程要求

- **幂等**：同一机器状态重复运行不应产生 diff。
- **安全**：collector 使用 allowlist，不读取 secrets 内容。
- **局部更新**：一项事实变化不应重写整个仓库。
- **可测试**：解析和规范化逻辑尽量与系统调用分离，可用 fixture 测试。
- **兼容缺失**：命令不存在、PATH 异常、非默认安装位置都属于正常输入。
- **可追溯**：易变化事实保留 `source`、`observed_at` 和可选 verification command。
- **模块化扩展**：新增软件类别优先新建 module，不扩大单个巨型 YAML。

## V1 暂不实现

- GUI；
- 常驻监控 daemon；
- 全量非开发软件采集；
- 多机同步模型；
- 自动安装/卸载/升级软件；
- 自动修改 PATH、代理、注册表或系统设置；
- 无 review 的自动提交和 push。

## V1 验收

在真实机器运行一次完整 sync 后，如果满足以下条件即可认为 V1 基础成立：

- 主要开发环境与已登记项目的信息足够完整；
- 关键版本、路径、安装/更新方式可重新验证；
- 没有 secret 或不必要的机器原始数据；
- 第二次无变化运行基本产生零 diff；
- 网页 GPT 仅通过 `CURRENT.md` + 少量按需文件即可正确理解本机环境；
- 新增一个软件类别或项目不需要调整现有目录架构。
