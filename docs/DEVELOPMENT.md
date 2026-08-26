# MachineContext 开发计划

## 当前阶段

当前处于 **V1 Phase G / Initial real-machine Full Audit**。Phase A-F 的首轮可执行基础已落地：共享 runtime、structured providers、candidate discovery、reconciliation、project records、validation/render/sync 均已接通；下一步是继续复核真实候选、补齐 provider/verifier 覆盖，并进行人工语义整理。

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

### Phase G — Initial real-machine Full Audit

第一次 Full Audit：

- 旧聊天线索只用来提高 discovery coverage；
- 对所有 historical hints 重新验证；
- 做 broad project/software candidate discovery；
- 复核 multi-install / nonstandard path；
- 对 role/status/purpose/conventions 做语义整理；
- 根据真实路径归纳安装/更新规范；
- 检查生成后的 `CURRENT.md` 是否足够支持网页 GPT 规划；
- 运行第二次 no-change scan 验证 idempotency。

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
