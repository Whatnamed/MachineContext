# MachineContext Collection Spec

本文档是采集范围的正式清单。**不要依赖临时 prompt 决定“这次该查什么”**。本地 collector 和 Agent 应以这里为准；需要新增采集项时先判断是否真的有决策价值，再扩展本规范。

原则：只收集对安装、更新、开发、迁移、排障和常用工具规划有帮助的信息；优先结构化事实，不保存无意义 raw dump；所有敏感边界同时受 `PRIVACY.md` 约束。

## 通用软件记录字段

对 runtime、CLI、开发工具、AI 工具以及未来普通软件，适用时记录：

| 字段 | 含义 |
|---|---|
| `id` | 稳定、唯一、与版本无关的 ID |
| `name` | 可读名称 |
| `category` | runtime / package-manager / sdk / cli / ai-tool / desktop-app 等 |
| `status` | active / inactive / legacy / testing / broken / unknown |
| `role` | primary / secondary / project-only / optional |
| `version` | 当前检测版本 |
| `executable` | 实际命令解析到的可执行文件路径 |
| `install.root` | 主要安装根目录（有意义时） |
| `install.method` | winget / vendor-installer / portable / npm-global / uv-tool / manual 等 |
| `install.scope` | user / machine / project 等 |
| `install.in_path` | 是否能通过预期 PATH 解析 |
| `install.update_method` | 推荐/当前更新途径 |
| `config_paths` | 有规划价值的配置位置，只记录路径，不读取敏感内容 |
| `data_paths` | 有规划价值的数据/cache 路径 |
| `verification.state` | verified / stale / pending / unavailable |
| `verification.source` | detected / manual / imported / inferred |
| `verification.observed_at` | ISO-8601 时间 |
| `verification.command` | 安全的版本/存在性验证命令 |
| `notes/constraints` | 非默认路径、兼容性、特殊行为等少量关键信息 |

不相关字段可以省略，不要为了 schema 对齐制造大量 null。

## A. Machine / OS

V1 采集：

- Windows product/name、edition、version/display version、build number；
- OS architecture；
- locale / preferred UI language（如果可安全、稳定检测）；
- timezone；
- PowerShell execution environment 中与脚本兼容性有关的信息；
- MachineContext 本地根目录。

默认不需要上传：真实 Windows 用户名、机器 hostname、设备序列号、Windows product key、Microsoft account 信息。

## B. Hardware

V1 采集：

- CPU model、architecture、logical/physical core count（有可靠来源时）；
- physical memory total；
- GPU model；
- GPU VRAM（可靠可得时）；
- 是否支持/启用常见虚拟化能力，仅在 WSL/Docker 等判断需要时记录。

不要采集硬件序列号或设备唯一标识。

## C. Storage / Drive roles

每个长期有意义的 volume 记录：

- drive letter / mount point；
- filesystem；
- total/free space；
- type（local/removable 等，可靠可得时）；
- 语义 role，例如 system / tools / development / projects / media，由检测结果与人工语义共同维护。

此外归纳重要目录根，例如 `D:\Tools`、`E:\Dev`、项目根等；先检测实际使用，再写入安装规范。

## D. Shells and command resolution

明确检查：

- Windows PowerShell（如存在）；
- PowerShell 7 (`pwsh`) version/path；
- `cmd.exe`；
- Git Bash / bash 的实际路径；
- `where.exe` / `Get-Command` 对关键工具的解析结果；
- WSL version、default distro、已安装 distro 列表（如存在）；
- PATH 中**与开发/工具规划有关**的条目摘要。

不要无差别上传全部环境变量值。环境变量默认只允许记录经过批准的名称/存在性。

## E. Development runtimes

至少探测下列 runtime 是否存在，并在存在时记录通用软件字段：

- Node.js；
- Python；
- Go；
- Rust (`rustc`, `cargo`, `rustup`)；
- Java/JDK；
- .NET SDK/runtime；
- Flutter / Dart；
- Ruby / PHP 等只在实际存在时记录，不要求为了清单安装。

## F. Package managers

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
- Chocolatey / Scoop（如存在）。

除版本/path 外，记录有决策价值的 global prefix/store/cache 位置；不要枚举所有全局 package 作为默认行为。

## G. SDK / compiler / build toolchain

至少关注：

- Git、Git LFS；
- Visual Studio edition/version/install path；
- 已安装的关键 VS workloads（例如 Desktop development with C++）；
- MSVC toolset version；
- Windows SDK version(s)；
- CMake；
- Ninja / Make（如存在）；
- Android Studio / Android SDK / adb（如存在）；
- 其他被长期项目真实使用的 SDK/编译器。

## H. Developer applications and cloud CLIs

至少探测/登记有价值的：

- VS Code；
- GitHub CLI (`gh`)；
- GitHub Desktop（如使用）；
- Docker Desktop / Docker Engine / Compose；
- Supabase CLI；
- Vercel CLI；
- Wrangler；
- Firebase CLI；
- AWS / Azure / Google Cloud CLI；
- 其他长期使用的开发工具。

不存在的工具不用生成大量 `not_installed` 记录；只有当“确认不存在”对当前规划长期有价值时才显式记录。

## I. AI / Agent tooling

单独记录在 `context/software/ai.yaml`。至少检查当前或历史上可能存在的：

- Codex CLI；
- Codex Desktop（可可靠检测版本时）；
- DSH；
- Agy（如实际安装）；
- Claude Code（如实际安装）；
- Gemini CLI（如实际安装）；
- OpenCodex 或相关 provider/harness；
- 本地 Codex/OpenAI bridge/server；
- 与这些工具有关的配置目录、默认 shell、local endpoint/port 等**非敏感事实**。

认证文件只能记录 `exists` 和必要的 normalized path，绝不读取/提交内容。

## J. Network / proxy / local services

仅记录对软件使用和开发排障有价值的上下文：

- 当前主要代理客户端及 role；
- system proxy / TUN 是否启用（可安全检测时）；
- 常用本地 proxy mixed/http/socks port；
- 终端是否通常直连等人工语义 policy；
- approved local developer services 的 bind address、port、用途；
- localhost bridge/API 服务关系；
- 与开发有关的重要网络 constraint。

不要上传代理订阅 URL、节点列表、用户名、密码、token 或完整代理配置。

## K. Projects

只登记需要长期上下文的项目。每个项目记录：

- stable `id`、name、status（active/paused/maintenance/archived/experimental）；
- local path；
- Git repository / remote；
- default/current working branch 在长期有意义时；
- workspace/project type；
- runtime refs；
- package manager refs；
- tool refs；
- service refs（Supabase/Vercel 等）；
- manifest/lockfile **路径**；
- 常用 dev/lint/typecheck/test/build 命令；
- 常用本地 dev port/url；
- 对本机环境有影响的 constraints；
- 与 MachineContext 中工具的 relationship。

不要复制项目完整 package dependency list。需要精确依赖时直接读取项目自己的 manifest/lockfile。

## L. Installation / update conventions

初次审计后归纳而不是预设：

- 各磁盘主要用途；
- standalone CLI / portable tool 常用根目录；
- runtime 常用安装位置；
- global package/cache/store 常用位置；
- SDK/大型工具是否倾向避开系统盘；
- project 常用根目录；
- 对 winget/vendor installer/portable/package-manager 的偏好；
- 更新时是否优先沿用原安装渠道；
- 哪些工具刻意不加 PATH；
- 非默认路径造成的 downstream dependency；
- 移动/升级某工具前必须检查的关系。

这些属于语义事实，允许人工/Agent 维护，但必须建立在机器真实现状上。

## M. Relationships

只记录能改善决策的关系，典型 relation：

- `uses_shell`；
- `requires`；
- `uses`；
- `provided_by`；
- `configured_with`；
- `reads_auth_from`（只表示关系，不读 auth 内容）；
- `serves` / `connects_to`；
- `deployed_by`；
- `used_by_project`。

例如“移动 Git Bash 会影响哪个 Agent preset”就应能通过 relationship 回答。

## N. Future: general software

非开发软件以后可以加入，不需要改核心模型。建议按 domain 新增 module，而不是把全部软件塞进 `development.yaml`：

- `general.yaml`：常用通用工具；
- `creative.yaml`：Figma、Adobe、3D/CAD、图像/视频等；
- `productivity.yaml`：Obsidian、Office、同步/笔记等；
- `browsers.yaml`：主要浏览器和重要 profile-independent 配置事实；
- `media.yaml`：只有确实会影响规划时再加。

仍然遵循“有决策价值才记录”。游戏、系统组件、VC redistributable 等不应默认成为完整资产清单。

## Refresh policy

- 安装/卸载/升级/迁移工具、修改 PATH、改变代理或新增长期项目后：事件触发 sync；
- 版本、路径、free space、本地服务等易变化事实：每次相关 sync 重新验证；
- role、项目 status、安装偏好：变化时人工/Agent 更新；
- 可选周期 full verify：后续根据实际使用频率决定，不在 V1 强制常驻监控。
