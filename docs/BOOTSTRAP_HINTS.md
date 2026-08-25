# Initial Audit Bootstrap Hints

> **重要：本文件不是当前机器事实，也不是 canonical context。**
>
> 这些内容来自此前对话/开发记录，仅用于第一次本机审计时提高查找效率。任何条目都可能已经升级、移动、卸载或改变配置。只有本地重新检测并验证后，才能写入 `context/`。

## System / hardware hints

- Windows 11。
- GPU 曾记录为 NVIDIA RTX 3070 Laptop。
- 常用开发环境为 Windows + PowerShell / Git / VS Code。

## Git / shells

历史记录曾出现：

- Git executable: `D:\Git\Git\cmd\git.exe`
- Git Bash: `D:\Git\Git\bin\bash.exe`
- 另一 bash: `D:\Git\Git\usr\bin\bash.exe`
- `C:\Program Files\Git\bin\bash.exe` 当时不存在。
- 曾发生工具 preset 假设默认 Git Bash 路径、但真实 Git 安装在 D 盘的问题。

审计重点：实际 `git` / `bash` command resolution、PATH、Git Bash 依赖关系。

## Node / package managers

历史记录曾出现：

- Node.js `v22.23.2`，executable `D:\Node.js\Node.js\node.exe`。
- 更早记录出现 Node `22.14.0`，说明版本会漂移。
- npm 曾记录 `10.9.8`，更早为 `10.9.2`。
- npm global prefix 曾为 `E:\Dev\npm-global`。

审计重点：当前版本、实际 executable、npm prefix/cache、pnpm/yarn/bun 是否存在。

## Python / uv

历史记录曾出现：

- `E:\Dev\uv\uv.exe`
- `E:\Dev\uv\uvx.exe`

Python / pip / conda 的完整现状此前没有可靠记录，需要本机重新检测。

## Supabase / cloud CLI

历史记录曾出现：

- Supabase CLI `2.109.1`
- `D:\Tools\SupabaseCLI\2.109.1\node_modules\.bin\supabase.cmd`
- 当时明确为未加入普通 PATH。

Vercel 被项目使用过，但 Vercel CLI 当前本机状态需要检测。Wrangler / Firebase / AWS / Azure / gcloud 等也应按 Collection Spec 探测，而不是假设存在。

## Codex / AI tooling

历史记录曾出现：

- Codex CLI `0.148.0`；更早一天记录为 `0.147.0`。
- Codex Desktop 曾出现 package/runtime 不同版本号，需要重新确认实际可用的版本来源。
- Codex data/session 路径位于 `%USERPROFILE%\.codex\...`。
- `%USERPROFILE%\.codex\auth.json` 曾存在；**只允许检查 exists/path，禁止读取或提交内容。**
- 曾使用 `.codex\visualizations`。

### DSH / OpenCodex

历史记录曾出现：

- DSH `v0.1.0-rc.6`，之后可能已有更新版本。
- command/path 曾出现 `D:\DSH\dsh.cmd`。
- preset 路径曾出现 `%USERPROFILE%\.dsh\.agent-presets\anchored-standard\agent.cordis.yml`。
- 曾安装 DSH Plugin Market / `dshmarket`。
- OpenCodex provider 曾指向 `http://localhost:10100/v1`。
- 曾配置 sol / terra / luna 等模型；这些属于工具配置语义，是否仍需要持久记录应在审计后判断。

### Codex bridge

历史记录曾出现：

- `openai-api-server-via-codex 0.2.0`
- endpoint `127.0.0.1:18080`，API base `/v1`，health `/healthz`
- config 曾位于 `%USERPROFILE%\.config\openai-api-server-via-codex\config.toml`
- controller/project 曾位于 `E:\Codex\CodexBridge`

审计重点：工具是否仍使用、版本、启动方式、端口、与 Codex auth 的关系；禁止采集凭据内容。

## SDK / compiler hints

历史记录曾确认或提到：

- Visual Studio 2022
- Desktop development with C++ workload
- MSVC v143
- CMake
- Windows 11 SDK
- Flutter

具体版本、install path、Windows SDK 版本、Flutter/Dart 版本均应重新检测。

## Developer applications

- VS Code 长期使用，但此前缺少可靠当前版本/安装路径记录。
- Obsidian 有使用记录，并与同步工具配合；它属于未来 general/productivity software 扩展候选，不要求 V1 开发环境阶段就做完整应用盘点。
- Docker 当前没有可靠结论，必须检测后再判断，不得因为旧记录缺失就写 `not_installed`。
- WSL 在 Codex Desktop 使用期间曾出现过 WSL 实例，但 distro / WSL1/2 / 当前用途不明确。

## Network / proxy hints

历史上存在多个客户端/阶段，必须区分 active 与 legacy：

- FLClash 是近期主要使用候选。
- Mihomo mixed port 曾记录为 `7988`。
- v2rayN 更早记录过 mixed port `10808`，更可能属于 legacy 状态。
- 曾有“不希望终端默认走代理”“TUN 按场景使用”等语义偏好；这些应由本机现状和用户规则确认后写进 conventions/network constraints。

不要读取或上传代理订阅、节点凭据或完整配置。

## Project candidates

### Morpho

历史记录：

- local path: `D:\联合设计工坊\Morpho`
- repository: `Whatnamed/Morpho`
- Node/npm 项目
- 使用 Supabase、Vercel
- dev server 曾使用 `127.0.0.1:3000`

项目自己的 package manifest / lockfile 才是详细依赖 Source of Truth。

### FLClash Traffic Ledger

历史记录：

- 开发副本曾位于 `E:\FlClash\flclash-traffic-ledger`
- 与 Flutter/Windows 工具链有关

需要确认该项目当前是否仍 active、paused 或 archived。

### ProxyLens

近期存在持续开发项目 ProxyLens。第一次 audit 可将它作为 project discovery 候选，但本文件没有可靠的 local path / repository / runtime 事实，必须本机/仓库重新确认。

## What is intentionally missing

以下内容此前没有足够可靠的当前信息，初次审计应明确检查：

- Python / pip / conda 的完整状态；
- pnpm / yarn / bun；
- Go；
- Rust；
- Java/JDK；
- .NET；
- Docker；
- Android SDK / adb；
- Git LFS；
- GitHub CLI / GitHub Desktop；
- 各工具真实 install/update method；
- 各磁盘容量、free space 与实际语义用途；
- WSL 当前状态；
- 当前长期项目清单；
- 当前软件安装目录规范。

这些“未知项”尤其不能靠聊天记忆补全，应作为第一次真实机器审计的一部分。
