# V1 Implementation Guide

本文档记录在真正写 collector 之前必须固定的实现边界。`DEVELOPMENT.md` 负责阶段/任务，`COLLECTION_SPEC.md` 负责收集内容，`DISCOVERY_DESIGN.md` 负责发现策略；本文档负责避免实现层常见的“第一版能跑、第二版就必须重构”。

## 1. Windows-first，不提前做伪跨平台

V1 runtime target 是当前 Windows 主机 + PowerShell 7。

数据模型不要写死到 Windows API 名称，但 collector 实现无需为了未来 macOS/Linux 抽象出复杂 platform framework。WSL 先作为独立 environment scope 记录 host-level 信息；不要把 distro 内部的 runtime 与 Windows runtime 混合。

## 2. Core collector 零自动安装依赖

运行 audit/sync 时不得：

- `Install-Module`；
- `pip/npm/winget/choco/scoop install`；
- 自动下载辅助 executable；
- 修改 PATH/Registry/Everything 设置；
- 启停与扫描无关的第三方服务。

可选 adapter 只有在已经存在时使用。缺少 provider 是正常状态，不是安装理由。

## 3. Canonical structured data 使用 JSON

V1 的 canonical structured context 使用 **JSON + Markdown**，不使用 YAML 作为机器维护的 canonical format。

原因：

- PowerShell 7 原生提供 `ConvertFrom-Json` / `ConvertTo-Json`；
- YAML 需要额外 parser/module 或自行实现，和“轻量、可维护、无 bootstrap dependency”冲突；
- JSON 对 ChatGPT/Codex 同样容易读取；
- 更容易做 deterministic serialization、schema validation 和 fixture test；
- 未来 Rust/TypeScript/其他实现都可以无缝读取。

约定：UTF-8、2-space indentation、稳定字段顺序、稳定数组排序、结尾 newline。禁止把格式化时间等无意义变化扩散到整个文件。

`CURRENT.md`、docs 仍使用 Markdown。

## 4. 同一实体分开 observed 与 curated ownership

最关键的数据所有权规则：**collector 只能拥有它能重新检测的字段，不能覆盖人工/Agent 语义。**

软件记录推荐形状：

```json
{
  "id": "node",
  "kind": "runtime",
  "observed": {
    "present": true,
    "version": "22.x",
    "executable": "D:\\...\\node.exe",
    "install": {},
    "evidence": []
  },
  "curated": {
    "status": "active",
    "role": "primary",
    "purpose": null,
    "constraints": []
  }
}
```

`observed`：脚本可覆盖/更新。

`curated`：脚本必须原样保留，除非用户/Agent 明确修改。

不要把 `role=primary` 简单等价为“PATH 第一个”。实际 command resolution 是 observed fact；“我主要想用哪个”是 curated intent。

## 5. Evidence-first reconciliation

Collector 输出不要直接成为 canonical entity。先产生 observation/candidate，再 reconcile。

推荐内部 observation：

```text
provider
provider_key
candidate_kind
name_hint
path/package_id
fields
confidence/evidence
collector_health
```

Reconciler 负责：

- 多 source 去重；
- stable ID；
- 字段级 source precedence；
- conflict warning；
- 保留 curated data；
- 决定 absent/unavailable，而不是 collector 自己删 item。

## 6. Freshness 不得制造全仓库时间戳噪声

不要在每次 scan 后给每个 item 改 `verified_at`，否则“没有变化”也会改几十/几百行。

V1 推荐：

- item 记录当前 value 的来源/证据以及必要的 `changed_at`；
- `.local/state.json` 保存本机精确 `last_checked_at` / per-provider diagnostics（不提交）；
- committed `context/status.json` 只保存发布级别的 freshness/collector-health 摘要；
- 只有实际发布运行（`scripts/sync.ps1` 未使用 `-NoPublish`）才刷新一次 verification heartbeat，允许 `status.json` 产生小 diff；`-NoPublish` proposal 必须保留既有 heartbeat；
- 业务事实没变时，其他 canonical files 应保持 byte-stable。

因此 V1 的幂等验收定义为：**零 semantic diff；除明确发布的 status heartbeat 外不产生数据噪声。**

## 7. Collector status 是一等数据

每个 provider 一次运行必须产生：

```text
success | partial | unavailable | timed_out | failed
```

并记录短 diagnostics/duration。

这决定了“missing evidence”能否解释成工具被删除。Provider failed 时绝不能因为本次没结果就把旧 item 删除。

## 8. 外部命令必须安全、可中止

封装统一 `Invoke-Probe`：

- 先 resolve executable；
- executable 与 arguments 分开传递；
- hard timeout；
- timeout kill process tree；
- stdout/stderr/exit code 分开；
- output size cap；
- no shell by default；
- diagnostics 标明 provider/probe；
- 不把完整 stderr/raw output直接持久化。

不要让每个 collector 自己发明一套 subprocess 逻辑。

## 9. Windows installed-app source 顺序

V1 推荐：

1. Registry Uninstall keys（HKLM/HKCU + 32/64 views）作为 Add/Remove Programs 基础 inventory；
2. winget 作为 package identity/update-channel enrichment；
3. MSIX/AppX 在出现缺口时增加专门 provider；
4. standard install roots 只做 candidate fallback；
5. Everything/文件索引解决 portable/custom-root/unknown discovery。

禁止使用 `Win32_Product` / `wmic product` 做常规 inventory。

Registry collector 不要 dump 整棵 key，只读取 allowlisted fields，例如 DisplayName / DisplayVersion / Publisher / InstallLocation / InstallSource / DisplayIcon / EstimatedSize / registry identity。`UninstallString` 默认只用于本地 inference，不直接提交，因为它可能包含不必要信息。

## 10. Command/runtime 不是单实例模型

对 Node/Python/Java 等，V1 需要允许：

- effective resolved installation；
- alternative installations；
- version manager；
- shim/alias；
- project-local/venv；
- WSL scope。

不要把所有 `python.exe` 合成一个“Python”，也不要把所有候选都当 primary。

WindowsApps/App Execution Alias 等 shim 必须经过实际 safe probe 才能认定 usable。

## 11. Project discovery 先找根，再读少量 manifest

不要扫源码内容。先依据 `.git`（包括 `.git` file）、manifest/lockfile/workspace fingerprints 聚类 candidate root，再有选择地读取：

- package manager identity；
- scripts/常用命令；
- tech stack summary；
- remote identity（必须 sanitize）；
- local service/config existence。

Remote URL 在写入前必须去掉 userinfo/token/query 等敏感部分。

Monorepo、worktree、submodule、nested repo、非 Git project 都必须有 fixture。

## 12. Package-manager inference 不能只看 package.json

Node project 的 package manager 判定顺序至少考虑：

1. `package.json#packageManager` / Corepack；
2. workspace metadata；
3. lockfile；
4. 才是 fallback/inference。

不能像某些简单 scanner 一样看到 `package.json` 就生成 `npm run dev`。

## 13. Privacy 在 parser 层实现，不靠最后 regex 补救

最终 secret scan 仍要保留，但真正的安全来自 collector 从一开始就只读取 allowlisted keys。

特别注意：

- Git remote 可嵌 token；
- npm/pip registry URL 可嵌 credential；
- MCP config 的 env/args 可含 secret；
- process commandline 经常含 token/path；
- proxy config 包含 subscription/credential；
- `.env` 只允许 exists/path；
- shell history 不采集；
- 浏览器 profile 不采集；
- hostname/外网 IP/真实用户名默认无决策价值。

## 14. Atomic update，不边扫边改 canonical

推荐实现：

```text
.local/staging
  <- collectors
  <- reconcile
  <- proposed JSON
        |
        v
validate structure/references/privacy
        |
        v
render CURRENT.md
        |
        v
atomic replace canonical files
        |
        v
git diff
```

任一步失败，旧 canonical context 保持完整。

## 15. Sync 与 Git working tree 规则

`sync.ps1` 默认：

- dirty working tree -> 停止，除非变化明确属于本次 MachineContext workflow；
- 开始前/发布前检查 remote divergence；
- 不自动 force push；
- push conflict -> 停止并 reconcile；
- local full publish 尽量一个逻辑 commit；
- `CURRENT.md` 加 GENERATED 标记，不允许把手工修改当 source of truth。

这样网页端 Agent 修改 docs/context 后，本地 scanner 不会静默覆盖。

## 16. Testing strategy

V1 不追求单元测试数量，重点覆盖“最容易把事实写错”的边界：

- missing command；
- command timeout/non-zero/stderr version；
- Windows PATH/PATHEXT；
- Registry 32/64 + user/machine dedupe；
- same app from Registry + winget + PATH；
- path move but stable package identity；
- provider failure must not imply removal；
- WindowsApps shim；
- multiple Python/Node installations；
- Git worktree `.git` file；
- monorepo/packageManager/lockfile resolution；
- symlink/reparse point；
- Unicode/中文 path；
- inaccessible directories；
- secret-bearing URL redaction；
- no-change scan byte-stability；
- CURRENT deterministic rendering；
- sync staging failure leaves canonical untouched。

## 17. Performance telemetry for development only

Initial Audit 应输出每个 collector 的 duration/result count/warning count 到本地 diagnostics。不要提交完整 raw diagnostics。

先得到真实 benchmark，再决定哪里需要并发。目标是让 Quick 明显比 Discover/Full 快，而不是承诺未经测量的固定秒数。

## 18. Future MCP/API surface

未来如果本地 Agent 频繁需要 live query，可在 canonical context 之上增加 read-only MCP/CLI：

```text
summary
get_item
search_items
get_project
get_relationships
get_install_guidance_context
refresh_scope
```

但 MCP 是读取/操作 surface，不是新的 source of truth。网页 GPT 仍通过 private GitHub + `CURRENT.md` 获得跨设备 context。
