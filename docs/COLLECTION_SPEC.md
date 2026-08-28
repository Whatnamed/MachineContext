# MachineContext Collection Spec

本文档是 V1 **“什么信息值得长期记录”** 的正式清单。不要依赖临时 prompt 决定本次该查什么。

`DISCOVERY_DESIGN.md` 负责“怎么发现用户自己也忘记的东西”；`IMPLEMENTATION_GUIDE.md` 负责具体实现边界；本文件只负责信息价值与字段范围。

原则：只收集对安装、更新、开发、迁移、排障和常用工具规划有帮助的信息；优先结构化事实，不保存无意义 raw dump；所有敏感边界同时受 `PRIVACY.md` 约束。

## 通用实体模型

对 runtime、CLI、开发工具、AI 工具以及未来普通软件，适用时使用：

```text
id                stable canonical identity
kind/category     runtime / package-manager / sdk / cli / ai-tool / desktop-app ...
name              readable display name
observed           collector/reconciler-owned facts
curated            user/agent-owned semantics
```

### 常见 observed fields

- `present`；
- `version`；
- `executable` / `command_resolution`；
- alternative installations（确有价值时）；
- `install.root`；
- `install.method`：winget / vendor-installer / portable / npm-global / uv-tool / manual / version-manager 等；
- `install.scope`：user / machine / project / environment；
- `install.package_id`；
- `install.update_method`；
- `config_paths` / `data_paths`（只记录安全 path/exists 信息）；
- `evidence`：Registry/winget/command/config/filesystem 等安全来源摘要；
- 环境 scope（Windows host / WSL / project-local 等需要区分时）。

### 常见 curated fields（按需填写，均为可选）

- 软件/AI 的 `status`：仅在用户明确指定特殊状态（如 legacy / compatibility-only / primary）时记录；普通已安装工具无需默认写入 `active` 或 `unknown`；
- project lifecycle 的 `status`：非强制字段，项目存在本身即表达其长期项目地位，仅在明确为 legacy / archived / throwaway 时记录；
- `role`：primary / secondary / project-only / optional（仅在有明确比较意义时使用）；
- `purpose`：项目或非显而易见的 AI/CLI 工具记录简短定位；普通知名软件无需重复百科解释；
- `constraints`；
- 少量 notes。

不相关字段完全省略。不要为了 schema 对齐制造大量空值或无意义默认标签。

**Routine collector 只更新 observed，不得覆盖 curated。**

## A. Machine / OS

V1 采集：

- Windows product/name、edition、version/display version、build number；
- OS architecture；
- locale / preferred UI language（安全、稳定可得时）；
- timezone；
- PowerShell execution environment 中与脚本兼容性有关的信息；
- Developer Mode、long-path support、virtualization 等确实影响开发/安装决策的 capability；
- MachineContext 本地根目录。

默认不记录：真实 Windows 用户名、hostname、设备序列号、product key、Microsoft account 信息。

## B. Hardware

- CPU model、architecture、logical/physical core count；
- physical memory total；
- GPU model；
- GPU VRAM（可靠可得时）；
- GPU driver version（对 CUDA/渲染/本地 AI 兼容性有价值时）；
- virtualization capability/status（仅在 WSL/Docker/VM 规划需要时）。

不要记录硬件序列号或设备唯一标识。

## C. Storage / Drive roles

每个长期有意义的 volume：

- drive letter / mount point；
- filesystem；
- total/free space；
- type（可靠可得时）；
- curated role：system / tools / development / projects / media 等。

归纳重要 directory roots，例如 `D:\Tools`、`E:\Dev`、project roots。先检测真实使用，再形成 conventions。

## D. Shells / terminal / command resolution

检查：

- Windows PowerShell；
- PowerShell 7 (`pwsh`) version/path；
- `cmd.exe`；
- Git Bash / bash 实际 path；
- Windows Terminal 等主要 terminal host（实际存在/使用时）；
- OpenSSH client/version（不读 private key）；
- `where.exe` / `Get-Command` 对关键工具的有效 resolution；
- PATH 中与开发/安装规划有关的条目摘要；
- shell profile/config normalized path + exists（必要时，不读敏感内容）。

特别识别 WindowsApps/App Execution Alias、shim、version manager 等：path hit 必须经过 safe verifier 才能认定 runtime/tool 可用。

不要上传环境变量值 dump。

## E. Environment scopes / WSL

V1 primary scope 是 Windows host。

记录：

- WSL 是否存在/version；
- default distro；
- installed distro list；
- 与 Windows host 的 relationship。

V1 不默认深入枚举每个 distro 的所有 Linux runtime/package。以后扩展时必须作为独立 scope/profile，不能把 Linux Node/Python 扁平合并进 Windows entity。

## F. Development runtimes

至少探测：

- Node.js；
- Python；
- Go；
- Rust (`rustc`, `cargo`, `rustup`)；
- Java/JDK；
- .NET SDK/runtime；
- Flutter / Dart；
- Ruby / PHP / Deno 等实际存在时记录。

需要允许 multiple installations，而不是把 runtime 当成单布尔值。

同时探测会改变 resolution/update 的 version manager：

- nvm-windows / nvm；
- fnm；
- Volta；
- pyenv；
- asdf / mise；
- conda 等实际存在者。

记录 `provided_by` / `managed_by` relationship，比单独两个版本更重要。

## G. Package managers

至少探测：

- npm；
- pnpm；
- yarn；
- bun；
- pip / pipx；
- uv / uvx；
- conda / mamba；
- cargo；
- winget；
- Chocolatey / Scoop（存在时）。

除 version/path 外，记录有决策价值的 global prefix/store/cache。

当 package-manager CLI 尚未通过 host verifier 时，允许只在 `.local` 记录 allowlisted store/cache 的 normalized path 与 exists 状态；store/cache 痕迹不能单独证明 CLI 可用、已安装或已卸载，也不能晋级 canonical `present` 或 `verified-absent`。

如使用非默认 registry/mirror/proxy，只记录安全 host/策略/“已配置”状态；禁止 credential-bearing URL/token/password。

默认不枚举所有 global package；只有对长期环境/项目关系有价值的 package 才进入 persistent context。

## H. SDK / compiler / build toolchain

至少关注：

- Git / Git LFS；
- Visual Studio edition/version/install path；
- 关键 VS workloads；
- MSVC toolset；
- Windows SDK version(s)；
- CMake；
- Ninja / Make；
- Android Studio / Android SDK / adb / NDK（存在时）；
- CUDA Toolkit / `nvcc`（存在且有意义时）；
- 其他长期项目实际使用的 SDK/compiler/debugger。

Git config 只记录跨项目开发行为相关的非敏感事实；不默认记录 user.email/credential/private remote。

## I. Developer applications / cloud / infra CLIs

至少探测/登记有价值的：

- VS Code；
- GitHub CLI / GitHub Desktop；
- Docker Desktop / Docker Engine / Compose；
- Kubernetes tooling (`kubectl`, minikube, kind 等)；
- Supabase CLI；
- Vercel CLI；
- Wrangler；
- Firebase CLI；
- AWS / Azure / Google Cloud CLI；
- PostgreSQL/MySQL/MariaDB/Redis 等本地开发服务/CLI（实际存在或项目使用时）；
- Terraform/Pulumi 等实际长期使用工具；
- 其他长期开发工具。

认证状态只有确有规划价值时才能以非敏感布尔/alias 表示，绝不保存 credential。

不存在的工具不要批量生成大量 `not_installed` item。

## J. Installed application inventory

V1 开发相关 software discovery 以 Windows structured sources 为主：

- HKLM/HKCU Uninstall Registry（含 32/64 view）；
- winget package match / export enrichment；
- 必要时 specialized MSIX/AppX provider；
- Program Files / LocalAppData / custom roots 只作为候选发现补充。

可记录的通用 app metadata：

- display/product name；
- version；
- publisher；
- normalized install location；
- safe package/vendor identity；
- install/update ownership/method；
- role/status（curated）。

禁止常规使用 `Win32_Product` / `wmic product`。

未来 General Software phase 才决定哪些普通应用进入长期 context；V1 可以在 `.local` 保留 broad candidates，不必把所有 Redistributable/driver/system component 推到 Git。

## K. AI / Agent tooling

Canonical module：`context/software/ai.json`。

至少检查当前/历史候选：

- Codex CLI / Desktop；
- DSH；
- Agy；
- Claude Code；
- Gemini CLI；
- OpenCodex/provider/harness；
- Cursor/Windsurf/其他 AI IDE（实际存在时）；
- local Codex/OpenAI bridge/server；
- skills/preset/plugin/MCP related directory/config existence；
- default shell / local endpoint / port 等非敏感关系。

Config parser 只能提取 allowlisted safe fields，例如 MCP server **name/scope**。不得把 env、token、credential、完整 args/config 序列化进 context。完整的 AI 配置投影与 MCP inventory 规范见下方 R 节。

认证文件只能记录 `exists` 与必要 normalized path。

## L. Network / proxy / local services

只记录对使用/开发/排障有长期价值的 context：

- 当前主要 proxy client + curated role；
- system proxy / TUN state；
- local mixed/http/socks port；
- terminal normally-direct 等 curated policy；
- approved local developer services：bind/port/purpose；
- localhost bridge/API relationship；
- local database/container daemon/dev server 等长期服务；
- 重要 DNS/registry/proxy constraint 的非敏感摘要。

不记录：subscription URL、节点列表、用户名/password/token、外网 IP 历史、完整 proxy config、raw network connections。

Allowlisted loopback listener diagnostics may retain only local ownership labels such as process name, parent process name, Windows service name/state/start mode, and whether an executable path was accessible. Do not retain PIDs, command lines, service arguments, or raw executable paths in canonical context; these diagnostics stay under ignored `.local` state.

## M. Projects

只把长期有用的 project 写进 `context/projects/`。每个 project 记录：

### observed

- stable ID/name；
- local path；
- sanitized Git repository/remote identity；
- workspace/project type；
- runtime refs；
- package-manager refs；
- tool refs；
- service refs；
- manifest/lockfile **路径**；
- safe dev/lint/typecheck/test/build commands；
- local dev endpoints；
- `.env*` 仅 filename/exists；
- 相关 machine relationship。

### curated

- lifecycle：active / paused / maintenance / archived / experimental；
- purpose；
- machine/environment constraints。

不要复制完整 dependency list。需要精确 package version 时读取 project 自己的 manifest/lockfile。

Package manager 判定优先 `packageManager`/workspace metadata/lockfile，不能看到 `package.json` 就默认 npm。

### Local-only project activity diagnostics

Discover/Full may collect bounded activity evidence for verified Git candidates that are eligible for canonical project promotion. This evidence remains under `.local` and may contain only:

- normalized project ID/path；
- current branch name；
- latest commit timestamp；
- Boolean tracked-file dirty state；
- per-probe verification status/failure reason。

不得记录 commit message、完整 `git status` 输出、文件路径列表、diff、源码或项目依赖内容。Activity evidence is for audit review only and must not automatically set project lifecycle, purpose, or other `curated` semantics.

## N. Installation / update conventions

Initial Audit 后基于真实机器归纳：

- 各盘主要用途；
- standalone CLI / portable tool roots；
- runtime 常用 location；
- global package/cache/store location；
- SDK/大型工具是否倾向避开 system disk；
- project roots；
- winget/vendor/portable/package-manager 偏好；
- update 是否沿原 install channel；
- 哪些工具刻意不进 PATH；
- 哪些 runtime 由 version manager 管理；
- non-default path downstream dependencies；
- move/update 前必须检查的 relationships。

这些主要属于 curated semantics，必须建立在 observed evidence 上。

## O. Relationships

只记录改善 planning/impact analysis 的关系，例如：

- `uses_shell`；
- `requires`；
- `uses`；
- `provided_by` / `managed_by`；
- `configured_with`；
- `reads_auth_from`（只表示关系）；
- `serves` / `connects_to` / `listens_on`；
- `deployed_by`；
- `used_by_project`。

Relationship 应区分 detected / inferred / curated origin，并可附 safe evidence。

## P. Discovery coverage requirements

Collection Spec 不能只靠上述 named list。

Full/Discover 必须具备：

- structured Windows installed-app sweep；
- project fingerprint discovery；
- configured/known root discovery；
- portable/custom-install candidate discovery；
- optional Everything-index discovery（已存在时）；
- bounded fallback（无 Everything 时）；
- candidate -> verifier -> reconciliation 流程。

Raw discovery 输出永远留在 `.local`，不直接进入 Git。

## Q. Future: general software

以后按 domain 新增 module，不改核心架构：

- `general.json`；
- `creative.json`（Figma/Adobe/3D/CAD/图像视频等）；
- `productivity.json`（Obsidian/Office/同步/笔记等）；
- `browsers.json`（profile-independent facts）；
- `media.json`（只有确实影响规划时）。

普通软件仍复用 observed/curated、version/path/install/update/evidence 模型。不要演变成 Windows 所有 package、游戏、system component 的完整 CMDB。

## R. AI & tool configuration profiles

AI harness 的 provider/model/MCP 配置会被用户频繁手工修改，并直接决定 Agent 行为。MachineContext 保存的不是 raw config 备份，而是 **source-specific per-field allowlist projection**：本地真实配置 → 每个工具一个明确 allowlist 的解析器，provider/model 级未知字段**默认丢弃**（字段名以 `unprojected_keys` 记录，值永不发布）→ 结构化、可审计、可编辑的安全投影。共享 sanitizer 只作为 defense-in-depth，不承担 allowlist 职责。

Allowlist 条目按预期形状声明：标量/标量序列字段使用 `scalar-leaf`（值意外变成嵌套 object 时整个字段拒绝并记 redaction，不再进入通用 walker）；动态键映射（如 effort→effort map、model→window map）使用 `scalars` 或 `__items__` 指向同一套严格标量叶子规格；只有预期本身就是嵌套对象的字段才使用嵌套 allowlist。因此未知字段和"形状升级为 object 的已知字段"都不会退回 denylist 兜底。

Canonical module：`context/configs/`（index + 每工具一个 profile 文件 + `mcp.json`）。

### 值得投影的字段（按工具真实 schema 保存，不改造成抽象统一模型）

- provider / model 的 id、name、display name；
- protocol / api / adapter（Chat Completions、Responses 等）；
- safe base URL（strip userinfo/query/fragment）；
- contextWindow / maxTokens / limit.context / limit.output；
- reasoning / thinking 配置：enabled、variants/efforts、defaultLevel/defaultVariant、requiresEffort、compat flags；
- modalities（input/output）；
- default model / modelRoles / routing / listen port / provider family selection 等 harness 级选择状态；
- web search provider 顺序、shellPath 等长期影响行为的安全字段；
- credential 字段只能以 `credentialEnvName`（就地改名）或 profile 级 `credential_env_names` 保存环境变量**名称**；无法映射为环境变量名的 credential 一律丢弃并记入 `redactions`。

### 语义标注

- profile 级 `value_basis: configured-local` 表示这些是本地配置声明；
- `wire_verification: not-wire-verified` 表示本地 override（如 contextWindow、reasoning efforts）未经上游 wire 验证，不得解读为模型客观能力；
- `observed` 是 collector 拥有的投影；`curated` 保留给用户/agent 语义，routine sync 不得覆盖。

### 敏感文件边界

- `.env*`、auth DB、credential store、session/history/usage 数据库只记录 normalized path + exists + role，永不读取内容；
- config 中混有真实 API key 的文件（如 ZCode config.json）使用 source-specific allowlist parser 读取，禁止“先复制再 regex”；
- 旧副本（如含 key 的 stale config copy）只登记 path/exists。

### MCP inventory

`context/configs/mcp.json` 只收存在用户配置的 MCP：

- server name、tool/scope、enabled（可得时）、transport、command（normalized）、safe URL；
- args 按序列检查：credential 类 flag（`--token`、`--api-key`、`-H`/`--header` 等）连同它消费的下一个 argv 一起丢弃并记 redaction，`--token=...` 形式单独丢弃；
- env 只保存变量名。

无文件级 MCP 配置的工具在 `unresolved` 中说明（OMP 的状态数据库永远不被读取）。

### 刷新与删除

- config profile 随 routine core scan 刷新（读取小文件，成本低）；
- 解析失败 ≠ 源消失：projector/provider 失败时旧 profile 原样保留；只有**确认源文件不存在**时，reconciliation 将 last-known profile 标为 `observed.source_state: stale`（附 `source_state_reason`），不再静默充当“当前配置”；
- 删除 profile 需要显式清理；fresh 投影写 `source_state: current`，index 登记每个模块的 `source_state`。

## Refresh policy

- install/uninstall/update/move、PATH/proxy 改动、新增长期 project 后：事件触发 sync；
- 日常：Quick；
- 怀疑遗漏/大量变化：Discover；
- 初次建库/周期深审计：Full；
- expensive detail：Enrich on demand；
- role/project status/install preference：人工/Agent 语义变更时更新；
- exact per-item last-check time 存本地 `.local`，published freshness 仅写 compact `context/status.json`。
