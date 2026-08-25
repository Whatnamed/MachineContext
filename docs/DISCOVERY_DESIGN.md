# Discovery & Reconciliation Design

`COLLECTION_SPEC.md` 解决“哪些信息值得记录”；本文档解决另一个不同的问题：**在用户自己都记不全本机环境时，MachineContext 怎样尽可能发现这些信息，同时保持快速、低噪声、可验证和隐私安全。**

## 核心原则

MachineContext 不采用“已知工具 checklist”与“全盘暴力扫描”二选一，而采用分层 pipeline：

```text
structured discovery + targeted probes + optional indexed discovery
                         |
                         v
                      candidates
                         |
                         v
               evidence reconciliation
                         |
                         v
                 targeted verification
                         |
                         v
              detected observations
                         |
                  + curated semantics
                         |
                         v
                   canonical context
```

**Discovery 发现候选，Verifier 证明事实，Reconciler 决定它们是否是同一个实体；AI/用户只维护脚本不能可靠知道的语义。**

## Scan profiles

V1 需要从一开始区分扫描强度，不要让“完整”变成“每次都扫最深”。

### Quick

日常 sync 默认模式。目标是重新验证已经知道的关键事实，并读取高信号、低成本结构化来源：

- OS / hardware / storage；
- canonical 中已有工具的 command/version/path；
- PATH resolution；
- Registry installed-app metadata；
- package-manager/tool-specific metadata；
- 已登记 projects 的 manifest/path/status；
- 已登记 local services / proxy state。

Quick 不做广泛 filesystem discovery。

### Discover

用于第一次 audit、安装/迁移大量工具后、或者怀疑 inventory 有遗漏时。Quick 之外增加：

- broad installed-app discovery；
- workspace/project fingerprint discovery；
- known installation roots；
- portable/custom-install candidate discovery；
- Everything index adapter（存在时）；
- 有边界的 fallback filesystem discovery（不存在 Everything 时）。

### Enrich

只对选中的 candidate/item 做相对昂贵的检查，例如：

- directory size；
- update availability；
- 更深入 installer metadata；
- framework/project detail；
- secondary runtime installations。

不要把 enrichment 自动塞进每次 Quick。

### Full

Initial Audit 使用的组合模式：`Quick + Discover + 必要的 selective Enrich`。Full 不是“读取所有文件内容”。

## Discovery source classes

### Tier 1 — Structured OS sources

优先级最高，通常也是最便宜、最稳定的来源：

- Windows Registry Uninstall entries；
- CIM / .NET system APIs；
- PowerShell built-in system providers；
- Windows package metadata；
- WSL/Windows features 等官方命令/API。

### Tier 2 — Tool-owned structured sources

工具自己最清楚自己的状态：

- `node --version`、`git --version` 等 verifier；
- package managers 的机器可读输出；
- Visual Studio `vswhere`；
- `dotnet --list-sdks`；
- `rustup toolchain list`；
- Docker/WSL/Flutter 等官方 CLI；
- config parser 只提取 allowlisted non-secret keys。

尽量使用 JSON/XML/API 输出而不是 locale-sensitive table text。

### Tier 3 — Known roots / fingerprints

针对 structured source 不覆盖的内容：

- configured workspace roots；
- 已知工具目录（`D:\Tools`、`E:\Dev` 等应由真实 audit 发现后配置）；
- project manifest fingerprints；
- portable/custom-install executable candidates；
- application-specific config existence。

目录 walk 必须 bounded、skip known heavy dirs、never follow symlink/reparse point by default。

### Tier 4 — Optional indexed broad discovery

如果已安装 Everything + `es.exe`，使用其现有索引做文件名/路径候选搜索。它只提升 discovery coverage/speed，不提高事实可信度。

Raw Everything results 只存在本地临时区，不进入 canonical 或 Git。

### Tier 5 — Bounded fallback discovery

Everything 不存在时，绝不退化为 `C:\` / `D:\` / `E:\` 无边界递归。

Fallback 只能在：

- configured workspace roots；
- top-level developer/tool roots；
- Program Files / LocalAppData Programs 等标准位置；
- 用户明确批准的新 root；

执行 depth/time/result-count bounded search。

## Candidate model

Broad discovery 不能直接写 canonical。每个 candidate 至少应有本地临时字段：

```text
candidate_id
kind_hint
name_hint
path
source
source_key
confidence_hint
evidence[]
```

Candidate storage 默认放在 `.local/` 或进程内，并被 `.gitignore` 排除。

典型 evidence：

- `command_resolves`；
- `version_probe_succeeded`；
- `registry_entry`；
- `winget_package_match`；
- `manifest_present`；
- `config_present`；
- `filesystem_name_match`。

单独一个 `filesystem_name_match` 永远不够成为高可信 canonical fact。

## Identity & deduplication

这是 V1 最容易做歪的地方之一。

同一个 VS Code 可能同时被 Registry、winget、PATH、Program Files 和文件索引发现；这些不是五个软件。

Identity 优先级应尽量使用稳定 vendor/package identity：

1. 明确 canonical tool ID（例如 `git`, `node`, `vscode`）；
2. package-manager/vendor stable ID（例如 winget package identifier）；
3. installer identity / app package identity；
4. normalized installation root + product metadata；
5. normalized path fallback。

**Display name 不得作为唯一 identity。** 路径也尽量不要成为首选 identity，否则一次迁移会被错误识别为 remove + add。

一个 canonical entity 可以保留多个 `evidence/source`，但只有一个稳定 `id`。

## Source precedence and conflicts

不同 source 对不同字段拥有不同可信度。不要用一个全局“哪个 source 更权威”。

典型规则：

- runtime effective version/path：成功执行的实际 resolved executable > installer display metadata；
- install method/package identity：package-manager/vendor metadata > 文件路径猜测；
- install root：installer metadata + executable location 交叉验证；
- semantic role：curated user/agent field > PATH 顺序推断；
- project dependency detail：项目自己 manifest > MachineContext inference。

如果两个高可信 source 对同一字段冲突，记录 warning/evidence，不能静默覆盖。

## Collector health & absence semantics

“没找到”不等于“不存在”。

每个 collector/provider 本次运行应有 health：

```text
success | partial | unavailable | timed_out | failed
```

只有 collector **成功完成且它对该事实有覆盖能力**时，缺失才算 negative evidence。

一个已存在的 canonical item 如果本次没被发现：

- provider failed/timed out -> 保留旧值并标记 verification problem；
- provider succeeded but one source missing -> 等待其他 evidence；
- 多个适用 source 一致证明消失 -> 才能进入 unavailable/removed decision；
- destructive removal from canonical 应发生在 reconcile 阶段，而不是 collector 直接删除。

## Project discovery

Project discovery 的单位是“项目根”，不是源码文件。

高信号 fingerprints 包括：

- `.git` **directory 或 file**（worktree/submodule 场景不能只判断 directory）；
- `package.json` / lockfiles / workspace files；
- `pyproject.toml`；
- `Cargo.toml`；
- `go.mod`；
- `pom.xml` / Gradle files；
- `pubspec.yaml`；
- `.sln` / project files；
- `CMakeLists.txt`；
- compose/Docker files 作为辅助 evidence。

需要处理：

- nested repo；
- Git worktree；
- submodule；
- monorepo/workspace；
- 非 Git project；
- archived/cache/vendor copies。

Package manager 不能靠“有 package.json 就是 npm”推断。优先读取 `packageManager` / Corepack 信息和 lockfile (`pnpm-lock.yaml`, `yarn.lock`, `package-lock.json`, `bun.lock*`)。

Project discovery 只产生候选。是否进入长期 `context/projects/` 还要看 lifecycle/用户价值，避免把临时 clone/cache 全变成长期 context。

## Runtime resolution and multiple installations

机器上“装了 Python/Node”通常不是一个布尔值。

需要区分：

- command 在当前 Windows host 的实际 resolution；
- version manager 提供的安装；
- alternative installations；
- Windows Store/App Execution Alias shim；
- project/venv-local runtime；
- WSL 内的 runtime。

V1 canonical 至少要避免把一个 shim/path match 错当成可用 runtime：**存在性发现后必须运行安全 verifier。**

Windows host 和 WSL 是不同 scope。V1 可以记录 WSL 发行版和 host relationship，但不要把 WSL 内的 Node/Python 与 Windows host 的工具无区分混在一起。深入 WSL inventory 留作后续 profile/scoped-context 扩展。

## Command execution policy

- external command 必须有 timeout；
- timeout 后应终止整个 process tree；
- 优先 executable path + argument array，不拼接 shell command string；
- 只有确实需要 shell semantics 时才启用 shell，并明确标注；
- stdout/stderr/exit code 分开处理；
- 有些 `--version` 输出在 stderr（Java 等），verifier 必须容忍；
- parser 优先结构化输出，文本 parser 必须 fixture test；
- collector failure 进入 diagnostics，不应让整个 scan 崩溃。

## Performance model

速度通过“少做无意义工作”获得，而不是先写复杂并发框架。

实现顺序：

1. 各 probe 有 timeout；
2. expensive work 从 Quick 移出；
3. source 可跳过；
4. bounded discovery；
5. 再对独立慢 probe 做有界并发。

Initial Audit 应记录 per-collector duration，后续再根据真实瓶颈设性能预算。不要在没有 benchmark 前为了并发重写 PowerShell architecture。

## Privacy model for discovery

以下 raw 数据默认**禁止进入 Git**：

- 全盘/Everything 完整路径结果；
- process command lines；
- network connection dump；
-完整 Registry dump；
- 完整 config/dotfile；
- shell history；
- browser/profile data；
- package-manager credentials；
- Git remote 中的 userinfo/token/query secrets。

进入 canonical 前必须 normalize/redact。例如 Git remote 只保留安全 remote URL/repository identity；custom package registry 只保留安全 host/是否配置，不保留 credential-bearing URL。

## Atomic publication

Collector 不直接边扫边覆盖 canonical files。

建议 pipeline：

```text
collect into .local/staging
-> reconcile
-> validate schema/references/privacy
-> render proposed canonical files + CURRENT.md
-> compare with working tree
-> atomic replace
-> git diff
```

Validation 失败时不得留下半更新状态。

## Git synchronization

本地 MachineContext 与网页 Agent 都可能修改 private repo，因此 `sync` 必须考虑并发作者：

- 默认不在 dirty working tree 上自动覆盖；
- publish 前检查 remote divergence；
- pull/fetch 不能静默丢掉网页端修改；
- push conflict 应停止并要求 reconcile；
- 一个完整 publish 尽量形成一个逻辑 commit，而不是每个 context file 一个 commit。

## Everything adapter acceptance

Everything integration 满足以下条件才进入 V1 Discover：

- 自动检测 `es.exe`/服务可用性；
- 不自动安装、不修改 Everything 设置；
- query 有 result limit / timeout；
- raw path list 不提交；
- Everything 不存在时功能正确降级；
- candidate 仍需 verifier；
- 对 Everything 的依赖状态在 diagnostics 中清晰可见。
