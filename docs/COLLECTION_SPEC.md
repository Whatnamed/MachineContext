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

### 常见 curated fields

- `status`：active / inactive / legacy / testing / broken / unknown；
- `role`：primary / secondary / project-only / optional；
- `purpose`；
- `constraints`；
- 少量 notes。

不相关字段可以省略。不要为了 schema 对齐制造大量 null。

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

Config parser 只能提取 allowlisted safe fields，例如 MCP server **name/scope**。不得把 env、token、credential、完整 args/config 序列化进 context。

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

## Refresh policy

- install/uninstall/update/move、PATH/proxy 改动、新增长期 project 后：事件触发 sync；
- 日常：Quick；
- 怀疑遗漏/大量变化：Discover；
- 初次建库/周期深审计：Full；
- expensive detail：Enrich on demand；
- role/project status/install preference：人工/Agent 语义变更时更新；
- exact per-item last-check time 存本地 `.local`，published freshness 仅写 compact `context/status.json`。
