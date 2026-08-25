# Reference Project Research

本文档记录在 V1 collector 开发前对相邻项目和系统能力的研究，以及 MachineContext 应该“借鉴、适配、拒绝”的结论。它不是第三方项目功能清单，而是本项目的工程决策依据。

## 总结结论

MachineContext **不直接以任何现有 inventory/MCP 项目作为运行时依赖，也不整体 fork/改造它们**。现有项目解决了部分相同问题，但 MachineContext 的核心差异是：

- Git 友好的长期、可审计 machine context，而不是只做本地 inventory；
- 同时服务网页 ChatGPT 和本地 Agent；
- 不只记录“有什么”，还记录安装/更新方式、角色、约束、项目关系与用户约定；
- 强调 detected facts 与 curated semantics 的所有权边界；
- Windows-first，且需要兼容非默认路径、portable 工具和多盘开发环境；
- 默认只读、隐私最小化、raw discovery 不上传。

因此策略是：**借鉴成熟做法，优先复用 Windows/现有工具提供的结构化数据接口；仅在有明显收益时提供可选 adapter。**

## IO Inventory (`elm1nst3r/IOInventory`)

这是目前最接近 MachineContext 的开源项目。其 Rust core 把不同 scan source 拆成独立 collector，并发执行；collector 内的外部命令有 timeout；结果进入本地 SQLite，支持 notes/tags、snapshot/diff、AGENT_MAP 导出和 MCP。

### 值得借鉴

1. **Collector 按 source 拆分**，而不是一个巨型 scanner。
2. **启用/禁用发生在 collector 执行前**，禁用 source 就完全不做工作。
3. **并发 + 单命令 timeout + fail-soft diagnostics**，单个坏工具不能卡住整个 scan。
4. **快路径与 enrichment 分离**。昂贵的 size/version/update 检查不应该拖慢每次扫描。
5. **Project discovery 使用 workspace roots + bounded depth + manifest fingerprint**，跳过 `node_modules`、`.git`、build/cache/venv 等目录，并且不 follow symlink。
6. **Stable item key**，让重扫后 notes/tags 仍能附着到同一个实体。
7. **Detected inventory 与 user notes/tags 分离存储**。这是 MachineContext 需要进一步强化的模式。
8. **Read-only agent access by default**。写操作必须显式开启。
9. **Warnings 是 scan 结果的一部分**，而不是吞掉错误后假装扫描完整。

### 不直接采用

1. 不引入 Tauri/Rust/SQLite 作为 V1 基础。MachineContext 的核心是 Git-readable context，而不是本地 GUI ledger。
2. 不复制 IO Inventory 的 Windows application collector。其 Windows 路径主要枚举 `Program Files` / `%LOCALAPPDATA%\Programs` 顶层目录，无法满足我们的版本、安装来源、update method 和非标准盘需求。
3. 不照搬 AI app 检测。其部分 app-bundle 逻辑明显以 macOS 为主，Windows 需要单独设计。
4. 不照搬 `domain + collector + name` 作为唯一 identity。MachineContext 同一软件可能同时由 Registry、winget、PATH、文件系统等多个 source 发现，需要 evidence reconciliation。
5. 不照搬只比较 version 的 snapshot diff。对 MachineContext，path、install method、manager、role、relationship、constraint 的变化同样重要；Git 已经承担大部分历史 diff。
6. 不照搬通过“看到目录/配置”就直接成为 canonical item 的策略。Broad discovery 只能产生 candidate，必须验证后才能提升为事实。

### 代码复用原则

IO Inventory 是 MIT，但当前计划仍以**独立实现、借鉴模式**为主。若未来确实复制了实质性代码，应在提交中明确来源并保留其许可证/版权要求；不要为了省几十行 scanner 代码引入长期来源耦合。

## DevEnvInfoServer / system_information_mcp

这个项目证明了“让 Agent 按需查询本机环境”本身是有价值的。它按 OS、hardware、Python、network、programs、compiler、container、GPU、process 等类别暴露 MCP tools，并能并发执行类别扫描。

### 值得借鉴

- Agent-facing API 应该是**按类别按需查询**，而不是每次把整台机器全部塞进上下文。
- Live information 与 stored context 可以并存；未来本地 MCP 可以作为 MachineContext 的可选读取面。
- GPU/CUDA、container、compiler、version manager、local services 等容易被普通“软件清单”忽略，确实值得作为开发环境 context。

### 明确不采用的做法

- scanner 启动时自动 `pip install` 缺失依赖：MachineContext audit 必须只读，不能为了扫描而改变机器。
- 一个近 50 KB 的单文件 scanner：不利于测试、来源隔离和扩展。
- 默认采集 process command line、用户名、network connections、shell history、SSH 等广泛信息：隐私风险和噪声远高于 MachineContext 的决策价值。
- Windows 软件 inventory 使用 `Win32_Product`/`wmic product`：这类查询并不适合作为本项目的 inventory source。
- 通过 shell 拼接命令字符串：V1 应尽量直接执行已解析 executable + argument list，避免 quoting/injection/locale 问题。

## envinfo

`envinfo` 的价值不在于直接成为依赖，而在于证明“短、可复制、面向诊断的环境摘要”非常有效。

MachineContext 的 `CURRENT.md` 可以继续采用相似思想：默认只给 Agent 最有决策价值的版本/环境摘要，需要更深信息再读取 canonical module。

可把 envinfo 或相似工具的输出作为开发测试时的**对照样本**，但不需要引入为运行时依赖。

## Windows Registry + winget

Windows 的 installed software 不应该靠全盘找 `.exe` 作为主方法。

V1 应优先使用：

1. Add/Remove Programs 对应的 Uninstall Registry keys（machine/user、32/64-bit views）；
2. `winget list` 作为广义 installed-app 视角；
3. `winget export --include-versions` 的 JSON 作为可匹配 package identity/update channel 的补充；
4. MSIX/AppX 等在实际缺口出现时增加专门 adapter；
5. 文件系统 discovery 用于 portable/custom-install/unknown 项，而不是替代 installer metadata。

不要使用 `Win32_Product` 作为普通 inventory collector。它只覆盖 Windows Installer 产品，而且查询会触发 MSI consistency check，既慢又可能带来副作用。

## Everything / ES CLI

Everything 对 MachineContext 的价值是**可选的 unknown-discovery accelerator**，不是 source of truth。

如果本机已安装并运行 Everything/`es.exe`，Deep discovery 可以快速查询：

- `.git` / `package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod` / `pubspec.yaml` 等 project fingerprints；
- `node.exe` / `python.exe` / `git.exe` / 特定 agent CLI 等可执行候选；
- 非标准盘上的 portable/custom-install 工具。

Everything 的索引只用于产生 candidate。原始结果不得提交到 GitHub；candidate 仍需由 verifier 确认身份、版本、role 和来源。

如果 Everything 不存在，MachineContext **不得为了扫描自动安装它**。Fallback 是 Registry/package-manager/known roots/workspace roots 的 bounded discovery，而不是无界全盘递归。

## osquery

osquery 的“把系统 inventory 暴露为结构化查询表”是很好的思想参考，尤其是 Windows installed-program fields。

但 V1 不值得为了单用户 Windows inventory 再引入一个较重的长期 runtime/service dependency。内置 Registry/CIM/winget 足以覆盖主要需求。未来如果用户本机已经使用 osquery，可作为 optional provider，而不是硬依赖。

## 最终 Adopt / Adapt / Reject

| 方向 | 决策 |
|---|---|
| Modular collectors | Adopt |
| Per-probe timeout / cancellation | Adopt |
| Collector health + warnings | Adopt |
| Concurrent independent probes | Adapt：有界并发，先测量再优化 |
| Fast scan + expensive enrichment | Adopt |
| Stable identity/fingerprint | Adopt，但做多 source reconciliation |
| Notes/semantics independent from detected facts | Adopt 并强化 |
| Workspace-root project discovery | Adopt |
| Full-disk recursive walk | Reject as default |
| Everything indexed discovery | Optional adapter |
| Registry + winget Windows inventory | Adopt |
| `Win32_Product` / `wmic product` inventory | Reject |
| SQLite as canonical store | Reject for V1 |
| GUI/Tauri as core | Reject for V1 |
| MCP read interface | Future optional surface |
| Auto install/update/uninstall during scan | Reject |
| Broad process/history/network dumps | Reject |

## Consequence for V1

V1 collector should not be implemented as “a long list of `Get-Command` calls”. It should implement a layered discovery/reconciliation pipeline defined in `DISCOVERY_DESIGN.md`, while `COLLECTION_SPEC.md` continues to define **what facts are valuable**.
