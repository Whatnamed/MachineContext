# MachineContext 开发计划

## 当前阶段

当前处于 **V1 Phase G1 / Initial Audit Closure**。Phase A-F 的首轮可执行基础与 G0-A 至 G0-H correctness hardening 已落地；第一次真实机器 Full Audit 已发布，VS Code `.cmd` host probe 已修复并重新验证。当前重复 Full 的 canonical proposal 在排除允许变化的 `status.json` heartbeat 后保持 semantic/逐文件稳定；`.local` raw diagnostics 与 live volatile facts 可变化。Quick 重复扫描也已验证 canonical context 无变化。G1 仍保持 partial，直到历史线索、unknown/candidate 和项目语义得到明确审查。

开始实现前必须阅读：

1. `AGENTS.md`
2. `docs/COLLECTION_SPEC.md`
3. `docs/DISCOVERY_DESIGN.md`
4. `docs/IMPLEMENTATION_GUIDE.md`
5. `PRIVACY.md`
6. `docs/BOOTSTRAP_HINTS.md`（仅作为历史查找线索）

## V1 交付目标

V1 完成时应满足：

1. 安全、只读地采集 Collection Spec 中 V1 必需事实；
2. 不只查已知工具，还能通过 Discover/Full 模式发现用户忘记的项目、portable/custom-install 工具和安装来源；
3. Discovery candidate 经过 evidence reconciliation + verifier 后才能成为 canonical fact；
4. canonical context 使用 JSON，并区分 collector-owned `observed` 与 user/agent-owned `curated`；
5. provider health 能区分 `success / partial / unavailable / timed_out / failed`，失败不能误判软件被卸载；
6. `CURRENT.md` 从 canonical data 生成，短、稳定、适合网页 AI 快读；
7. push 前完成 schema/reference/privacy validation，raw discovery 不进入 Git；
8. 同步流程使用 staging + atomic publication，失败不能留下半更新状态；
9. 同一真实实体来自 Registry/winget/PATH/filesystem 等多个 source 时能正确去重；
10. 项目 registry 只保存环境级 context，不复制项目完整依赖；
11. 初次审计后形成真实安装/更新目录习惯；
12. 无机器事实变化的重复运行保持零 semantic diff。

## 实现顺序

### Phase A — Core runtime / shared libraries

先写公共基础，不要先堆几十个 collector：

- deterministic JSON read/write；
- path normalization/redaction；
- `Invoke-Probe`：executable + argument list、timeout、kill tree、stdout/stderr/exit code/output cap；
- provider diagnostics/health；
- `.local/` staging/state；
- stable sorting / stable IDs helpers；
- privacy-safe URL/path normalization。

这一步必须先有 fixture tests。否则后面每个 collector 都会复制错误的 subprocess/path/serialization 逻辑。

### Phase B — Cheap structured providers (Quick foundation)

按 source/domain 拆文件，优先实现最可靠的 Windows facts：

- system / hardware / storage via PowerShell/.NET/CIM；
- Registry Uninstall inventory（HKLM/HKCU、32/64 views）；
- shells / PATH / command resolution；
- runtimes/version managers；
- package managers；
- Git / VS / SDK/build tools；
- AI tooling；
- WSL host-level state；
- relevant network/proxy/local-service state。

明确禁止 `Win32_Product`/`wmic product` 常规 inventory。

### Phase C — Discovery providers

实现未知项发现，而不是扩大 checklist：

- project fingerprints under configured workspace roots；
- standard/known install roots；
- winget identity/export enrichment；
- optional Everything/`es.exe` adapter；
- bounded filesystem fallback。

Discovery 只输出 candidate/evidence，raw result 留在 `.local/`。

Everything adapter 必须 optional：不存在时不安装、不报 whole-scan failure、功能正确降级。

### Phase D — Identity / reconciliation / verification

这是 V1 的核心逻辑，不应推迟到“数据多了再说”。

实现：

- canonical stable ID；
- multi-source dedupe；
- field-level source precedence；
- high-confidence conflict diagnostics；
- candidate -> verified entity promotion；
- multiple runtime installations / shim / version-manager relationship；
- previous entity missing 时的 safe absence semantics；
- preserve `curated` while updating `observed`。

### Phase E — Project model

基于 project candidates 做长期 registry：

- `.git` directory/file、worktree/submodule；
- package manager from `packageManager`/workspace/lockfile；
- monorepo/nested repo handling；
- sanitized remote identity；
- scripts/manifest/endpoints/environment-file existence；
- active/paused/etc. 由 curated semantics 决定。

不要读取项目源码来“理解项目”，也不要把临时 clone/cache 自动登记为长期 project。

### Phase F — Validate / render / sync

实现：

- `validate.ps1`：JSON parse/schema-ish contract、stable IDs、reference integrity、privacy patterns、forbidden files；
- `render.ps1`：deterministic `CURRENT.md`；
- `verify.ps1`：scope/provider-based re-verification；
- `sync.ps1`：Quick/Discover/Full mode orchestration；
- staging -> validate -> render -> atomic replace -> git diff；
- dirty tree / remote divergence safety。

V1 默认不无 review 自动 commit/push。可靠后再增加显式 `-Commit` / `-Push`。

### Phase G0 — Correctness Hardening

在 Initial Audit Closure 前，先修复会污染长期 canonical 信任边界的基础问题：

- G0-A：明确 Scalar/Mapping/Sequence 分类；递归 clone 和 deterministic JSON 不得通过 JSON round-trip 猜类型，也不得展开 .NET collection metadata；补齐 software/project/machine/relationship contract validation 与 fresh fixture gate；
- G0-B：将持久化 Windows host PATH 与当前 collector process PATH 分离；host canonical 只发布 Machine/User persistent PATH，进程 PATH/`Get-Command` 结果只进入 `.local` diagnostics；保留 `wsl:<distro>` 作为未来 scoped context 的保留命名；
- G0-C：已接入 dedicated verifiers：Git-for-Windows/Git Bash 安装根、Windows normalized family、NVIDIA `nvidia-smi` VRAM、Visual Studio/vswhere + MSVC/Windows SDK + Native Desktop workload、Codex CLI/Desktop、Supabase CLI、VS Code CLI 与 .NET SDK/runtime 列表；generic command probes 不再承担这些高价值 identity 的最终事实。
- G0-D：已加入 `verified-present` / `unverified` / `stale` / `verified-absent` observation state；failed/timeout 通过 `.local` verification events 保留旧 observed，只有高置信度适用的成功 absence check 才能写 `present: false` + `last_known`；provider health 继续独立聚合，optional provider 不升级 whole-run failure。
- G0-E：项目 fingerprint discovery 使用 project/workspace/developer/tool/sdk/cache root policy；只有 project-root 下的 `.git` directory/file 才具备自动晋级资格，manifest-only 与 SDK/cache/vendor/unknown candidates 保留在 `.local`；项目名称优先使用 curated、repository basename、manifest name、directory name。
- G0-F：增加 bounded high-value executable fingerprint fallback；Everything/`es.exe` 仅在本机已有时查询项目与工具 patterns，所有结果保持低置信度 candidate/evidence，不直接写 canonical，并记录扫描预算与 optional provider health。
- G0-G：将 provider version banner 归一化为短 semantic version；无法安全解析的 banner 从 canonical `observed.version` 移除，原始输入只以 hash 形式留在 `.local` diagnostics；历史 software/shell records 在 reconciliation 时走同一规则。
- G0-H：只从 `verified-present` 的结构化观察和强路径证据生成 `provided_by` / project runtime/package-manager relationships；非晋级 project candidates、fallback shims 和 provider failure 不得生成或改写 canonical relationship。
- G0 gate 已关闭：测试与 Quick/`sync -NoPublish` 闭环已运行；旧 canonical validation pollution 通过显式 staged migration 修复，只有列出的非项目 root 历史 project 记录才会在 publish 时原子删除；OrderedDictionary 输入的 software/shell/project/relationship 数组也已使用显式 stable-key sorting。
- 每个 G0 子阶段均先实现、测试、自审计；后续变更继续保持同样的 staging、validation 和 no-change scan gate。

### Phase G1 — Initial real-machine Full Audit Closure

当前进度（2026-08-26）：

- Full Audit #1 已发布，provider aggregate 为 `partial`；structured canonical、项目 registry、relationships 和 `CURRENT.md` 已更新。
- VS Code `1.134.0` 已通过带空格路径的 `.cmd` safe probe，写入 canonical `code` entity；host-authoritative provider 随之从 `partial` 变为 `success`。
- VS Code 修复后的 Full repeat（20 个 canonical/Markdown proposal 文件）与当前仓库逐字节一致，`changed_files=[]`，validation 通过。
- VS Code 修复后的 Quick #1/#2 的 canonical context 除允许的 `status.json` verification metadata 外完全一致；两次均未发布。
- 当前 Full repeats `20260826-102534495-34fd2444` / `20260826-102623197-8b7ddaa8` 均为 `success`、293 candidates、`changed_files=[]`；两次 proposed canonical context 除 `status.json` 外完全一致。local diagnostics 仅出现 bounded discovery `visited_directories` 的 480→469 变化，属于本机扫描 volatility，不是 canonical semantic drift。
- G2 hardening 后的 Full no-publish `20260826-110930082-f2092b2a` 仍为 `success`、293 candidates、`changed_files=[]`，validation 通过；未发布 canonical，Everything unavailable 与 bounded fallback partial 保持为已知 optional/coverage 状态。
- Native Desktop workload verifier 发布后的 Full run `20260826-114713082-ecd921ba` 为 `success`、294 candidates、validation 通过；Full no-publish repeat `20260826-114845414-e4404102` 保持 `visual-studio.desktop_cpp_workload=verified-present` 且与 canonical evidence byte-equal。
- 嵌套 verifier failure hardening 后的 Full publish `20260826-120805036-a6dfe909` 为 `success`、294 candidates、validation 通过；发布 diff 仅包含真实 C: 存储变化与最新 ignored audit-closure timestamp 投影，未改变软件、项目或关系语义。
- 只读 listener check 将当前 `127.0.0.1:7988` 关联到 `FlClashCore -> FlClashHelperService.exe`（`Running/Auto`）；历史 `10808`、`10100`、`18080` 无 listener，但尚不足以自动决定 proxy primary 或 FlClash project lifecycle。
- Full/Discover 现通过 optional `project-activity-local` provider 将八个 promotion-eligible Git project 的 branch、latest commit time、tracked dirty Boolean 和 probe status 保存在 `.local`；这些证据不自动写入 lifecycle/purpose 等 `curated` 语义。
- 历史线索闭环保存在 ignored `.local/audit-closure.json`；该文件明确保留 unresolved/unknown，不将 provider failure 推断为卸载。
- `scripts/audit.ps1` 提供只读 closure contract/projection review；默认允许当前 `partial` closure，`-RequireVerified` 可作为进入后续阶段前的显式 gate，命令不写入 `.local` 或 canonical。
- `scripts/review.ps1` 现在同时审查 `.local/audit-closure.json` 与 `.local/g2-semantic-review.json`；semantic suggestions、project buckets 和 unresolved checks 必须保留 evidence、`canonical_write=false` 与 confirmation gate，candidate/unverified 不能声明 absence。
- runtimes provider 现在把 pnpm 的 allowlisted host-path/store evidence 留在 `.local`；当前观察到 `%LOCALAPPDATA%\pnpm\store` 存在但没有 persistent executable，因此仍保持 `pnpm` unverified，不推断 installed/absent。
- `context/status.json` 现明确区分 `provider_state` 与 `audit_closure`；audit closure 可显式记录按设计接受的 unknown，只有 open unknown/conflict/unresolved 才阻塞顶层 `state=verified`，因此当前仍因 pnpm、项目语义和 bridge/proxy 语义保持 `partial`。
- G2 curation validator 现区分 software/AI operational status 与 project lifecycle status：项目遵循 `context/projects/index.json.project_policy.statuses` 加 `unknown`，软件仍使用通用 curated status；本次只修正确认 contract，未写入任何 curated 值。
- G1 尚未宣称完成：需要用户审查项目 active/legacy/purpose、安装/更新 ownership、bridge/proxy 语义和剩余 unknown/candidate 后，才能进入 G2 curated semantics。
- standalone `scripts/verify.ps1 -Mode Quick` 已修复未传 `-Provider` 时的 StrictMode null `.Count` 崩溃，并由真实入口回归测试覆盖；该入口仍只写 ignored `.local` staging，不修改 canonical。

第一次 Full Audit：

- 旧聊天线索只用来提高 discovery coverage；
- 对所有 historical hints 重新验证；
- 做 broad project/software candidate discovery；
- 复核 multi-install / nonstandard path；
- 对 role/status/purpose/conventions 做语义整理；
- 根据真实路径归纳安装/更新规范；
- 检查生成后的 `CURRENT.md` 是否足够支持网页 GPT 规划；
- 运行第二次 no-change scan 验证 idempotency。

### Phase G2 — Curated semantics and maintenance baseline

在 G1 事实收敛后，由用户/agent 明确确认高价值语义：

- active/legacy/testing/broken 等状态、primary/secondary/project-only 角色；
- 安装/更新目录习惯、例外与工具之间的关系；
- 仍为 unknown/conflict 的事实及需要再次验证的 provider；
- 只把稳定、可解释、对后续规划有帮助的判断写入 `curated`。
- `scripts/curate.ps1` 已提供 confirmation-manifest 基础设施：默认只生成 dry-run plan，只有显式 `-Apply` 才能更新现有实体的 allowlisted `curated` 字段或已确认 conventions；manifest 中出现 `observed`、未知 stable ID、空更新集、非法时间、review 外 evidence 或缺少 evidence/confirmation 时直接拒绝。当前没有任何确认 manifest 被应用。

## 代码组织建议

```text
scripts/
  collect.ps1
  verify.ps1
  render.ps1
  validate.ps1
  sync.ps1
  collectors/
    system.ps1
    registry-apps.ps1
    runtimes.ps1
    package-managers.ps1
    toolchains.ps1
    ai-tools.ps1
    projects.ps1
    discovery-everything.ps1
    ...
  lib/
    probe.ps1
    normalize.ps1
    environment.ps1
    reconcile.ps1
    privacy.ps1
    json.ps1
    ...

tests/
  fixtures/

.local/               # ignored; staging/raw candidates/diagnostics

context/
  status.json
  machine.json
  network.json
  conventions.json
  relationships.json
  software/
  projects/
```

文件名只是建议，职责边界比具体命名重要。

## 关键工程要求

- **Read-only**：scan 不改变机器。
- **Fail-soft**：一个 provider 失败不阻塞整个 scan。
- **Timeout**：所有外部 command probe 都有硬超时。
- **Evidence-first**：filesystem hit 不是 truth。
- **Identity-safe**：同一软件多 source 不重复；path move 不轻易变 remove+add。
- **Ownership-safe**：collector 不覆盖 curated fields。
- **Atomic**：validation 失败旧 canonical 保持完整。
- **Idempotent**：no-change scan 零 semantic diff；必要 heartbeat 限于 compact status。
- **Privacy by construction**：parser allowlist 优先于最后 regex redaction。
- **Locale-tolerant**：优先 JSON/API/Registry，文本 parser 必须 fixture test。
- **Unicode-safe**：中文/空格路径必须是一等测试场景。
- **Scope-aware**：Windows/WSL/project-local 环境不能扁平混合。
- **Measured performance**：记录 collector duration，再决定是否并发优化。

## V1 暂不实现

- GUI；
- 常驻 daemon；
- 全量普通软件深度语义化；
- 多机器模型；
- 深入扫描每个 WSL distro；
- 自动安装 Everything/osquery/collector dependencies；
- 自动安装/卸载/升级软件；
- 自动修改 PATH、代理、注册表或系统设置；
- write-enabled MCP；
- 无 review 的自动 force/commit/push。

## V1 验收

完成 Initial Full Audit 后满足：

- 主要开发环境、AI 工具、关键本地服务与长期项目足够完整；
- 已知历史线索都被验证或明确标为不存在/未知；
- Discover 模式能额外发现 checklist 未显式列出的候选；
- 关键版本/path/install/update ownership 可重新验证；
- Registry + winget + command + filesystem 重叠结果正确去重；
- provider failure 测试不会造成虚假 removal；
- 无 secrets/raw full-disk dump；
- 第二次无变化运行只有允许的 compact verification metadata 变化，其他 canonical byte-stable；
- `CURRENT.md` + 少量按需 JSON 足够让网页 GPT 正确理解环境；
- 新增 software module / project / provider 不需要调整核心目录和 identity model。
