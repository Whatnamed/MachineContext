# Operations Runbook(运维操作手册)

本文件是 **"机器发生变化 → 仓库记录更新 → 云端同步"** 的唯一操作参考。

分工边界:`AGENTS.md` 只含全局规则;`PRODUCT.md`/`ARCHITECTURE.md` 讲理念与结构;`COLLECTION_SPEC.md` 定义采集价值的长期契约;`SCHEMA.md` 定义数据契约;`PRIVACY.md` 定义红线。本文件只回答三个问题:**去哪里收集、收集哪些信息、记录到哪里,以及收集/记录之后怎么同步上线**。

---

## 1. 环境要求(操作前必读)

- **必须用 PowerShell 7+(`pwsh`)运行所有脚本**。Windows PowerShell 5.1 会在 `SHA256::HashData` 处失败(.NET Framework 缺该方法)。
- **始终显式传 `-RepoRoot E:\MachineContext`**。部分调用环境下 `$PSScriptRoot` 为空,依赖它的默认参数会绑定失败。
- **推送前置条件:本地代理 `127.0.0.1:7988` 必须在运行**。`~/.gitconfig` 对 `github.com` 配置了 per-URL 代理;代理未开时 `git push` 报 `Failed to connect to github.com port 443 via 127.0.0.1`。正确处理:**请用户开启代理**,然后重试。**绝不能修改 git 配置、代理设置或绕过代理直连**。
- 仓库主分支为 `main`;**禁止 force push**;`.local/` 内容永不提交。

## 2. 标准同步流程

### 2.1 什么算"机器发生了变化"(触发器)

- 新装 / 升级 / 卸载任何被记录的软件或 AI 工具;
- AI 工具配置变更:provider、模型、上下文窗口、MCP 服务器、思考档位等(多数工具是**改配置文件**,注意 §4 各工具的源文件位置);
- 新增长期项目、项目用途变化;
- 代理 / 网络状态变化(系统代理开关、监听端口);
- 安装 / 更新习惯变化(应更新 `conventions.json` 的 curated 语义)。

### 2.2 命令一览

| 命令 | 用途 | 备注 |
|---|---|---|
| `pwsh scripts/sync.ps1 -RepoRoot E:\MachineContext` | 采集 → 对账 → 校验 → 渲染 → 原子发布 | 默认 Quick 模式;日常用这个 |
| `… sync.ps1 … -AllowDirty` | 工作树有未提交变更时允许继续 | 仅当变更属于本次 MachineContext 工作流(如文档改动与采集同批) |
| `… sync.ps1 … -NoPublish` | 干跑:只生成 staging 提案,不改 canonical | 验证"零变化扫描应无 diff"用 |
| `pwsh scripts/validate.ps1 -RepoRoot …` | 单独跑 schema/引用/隐私校验 | sync 内部已含;单独复跑用于确认 |
| `pwsh scripts/render.ps1 -RepoRoot …` | 单独重渲染 CURRENT.md | 应字节稳定 |
| `pwsh tests/run-tests.ps1` | 全量测试(41+ 断言块) | 任何脚本/采集逻辑改动后必跑 |
| `pwsh scripts/verify.ps1 -Mode Quick` | 按 provider 重新验证,只写 `.local` | 不改 canonical |
| `pwsh scripts/audit.ps1` / `review.ps1` | 只读审查 closure/语义建议契约 | 排查审计状态用 |
| `pwsh scripts/curate.ps1 -RepoRoot … -ConfirmationPath <manifest.json>` | 消费 curated 确认 manifest：默认 dry-run 生成 plan，`-Apply` 才写库 | manifest 形状见 `docs/examples/curate-confirmation.example.json`；批量语义更新用，见 §6 |

### 2.3 Gate 顺序(每次发布前必须全部通过)

1. `tests/run-tests.ps1` 全部 PASS(改动采集逻辑/测试时;纯文档变更可跳过);
2. `sync.ps1` 运行,overall health success、validation ok;
3. `git diff` 逐行检查 canonical 变化:只有预期漂移,无意外字段;
4. **对照用户口述的变更逐条确认已落到 diff**——尤其注意两条不会自动发生的记录:
   - **新装的软件不会自动晋级实体**:registry 候选只进观察流。用户提到装了新工具而 diff 里没有它时,查注册表卸载项确认版本/位置,按 §6(一次性实体添加)或 §7(带采集能力)入库;
   - **新工具的配置不会被采集**:只有 §4 列出的工具才有 profile;新工具需要按 §7 增加采集能力;
5. `validate.ps1` 0 findings;
6. **二次 sync 幂等**:再跑一次 sync,除 `context/status.json` 的 `verified_at` 心跳外无新 diff(这证明发布是收敛的,evidence 没有反复累积);
7. privacy sweep:对 `git diff context/` 做一次 secret 形状检查(`sk-`、`opaque`、`authorization`、`bearer`、token 形状),确认干净。

### 2.4 提交与推送约定

- **分块提交**,每块一个逻辑单元:
  - 能力/脚本/测试/文档变更 → 一个 commit(`fix(scope): …` / `feat(scope): …`);
  - canonical 数据发布 → 单独一个 commit(`chore(context): publish …`),message 里列清发布内容与例行漂移;
  - 一次性数据修正(如 evidence 清理、实体纠正)放在对应 publish commit 里并说明原因。
- commit message 用英文,风格参照 `git log`;canonical 发布 commit 必须说明"哪些是真实漂移"以免审查者误判回归。
- 推送:`git push origin main`。先确认代理在运行(§1);推送失败先查代理,**不要动配置**。
- 推送后可用 `git status -sb` 确认 `## main...origin/main` 无 ahead/behind。

### 2.5 常见失败与处理

| 症状 | 原因 | 处理 |
|---|---|---|
| sync 拒绝运行(dirty working tree) | 工作树有未提交变更 | 变更属于本工作流则加 `-AllowDirty`;否则先处理无关变更 |
| `Split-Path … 空字符串` 报错 | `$PSScriptRoot` 为空 | 显式传 `-RepoRoot`;改用 `pwsh` 而非 `powershell` |
| `SHA256 不包含 HashData` | 用了 Windows PowerShell 5.1 | 换 `pwsh` |
| validate 出现 findings | canonical 数据违反契约 | **修数据,不绕过校验**;常见:未归一化的用户路径、credential 形状键 |
| push 报 `Failed to connect … 127.0.0.1:7988` | 本地代理未运行 | 请用户开启代理后重试;禁止改 git/代理配置 |
| push 报 remote divergence | 远端有本地没有的提交 | 先 `git fetch` + 对账,禁止 force push |
| 测试断言 `property cannot be found` | fixture 与采集输出形状不一致 | 先核对真实源文件形状,再改 fixture/断言 |

## 3. 信息地图(什么信息 → 去哪收集 → 记录到哪)

| 信息类别 | 采集源(真机哪里) | 记录位置(canonical) | 刷新方式 |
|---|---|---|---|
| OS / 硬件 / 存储 / Shell / PATH | CIM、Registry、命令探测(自动) | `context/machine.json` | routine Quick,全自动 |
| 网络 / 代理 / 本地端口 | 系统代理状态 + loopback listener 检查 | `context/network.json` | routine,全自动 |
| 开发 runtime / 工具链 / 包管理器 | PATH 解析 + `--version` 探测 + 专用 verifier | `context/software/development.json` | routine,全自动 |
| AI / Agent 工具实体 | PATH 探测 + HKCU/HKLM 卸载表 + Appx 清单 | `context/software/ai.json` | routine + 补充(§8) |
| **AI 配置投影** | **各工具配置文件(§4 逐工具)** | `context/configs/ai/<tool>.json` | routine Quick(读小文件) |
| **MCP 服务器** | 四个 MCP 配置源(§4.7) | `context/configs/mcp.json` | routine Quick |
| 长期项目 | workspace roots 指纹 + manifest | `context/projects/*.json` | Discover / Full |
| 普通软件 | HKCU/HKLM 卸载表(候选) | `context/software/{creative,productivity,…}.json` | 补充扫描,晋级需确认 |
| 语义 / 用途 / 状态 / 使用关系 | **用户确认**(对话或 manifest) | 对应记录的 `curated` 字段 | 显式操作(§6) |
| 验证状态 / provider 健康 | 每次 sync 的 provider 运行结果 | `context/status.json` | 每次发布刷一次心跳 |
| 渲染入口视图 | 以上全部 | `CURRENT.md`(生成物,**不要手改**) | sync/render 自动 |

原则提醒:**canonical JSON 是唯一事实**,CURRENT.md 只是生成视图;evidence 只增不减;`observed` 归 collector、`curated` 归用户/agent。

## 4. 复杂对象采集详解(AI harness 逐工具)

> 这些是信息量最大、变更最频繁的对象。每节给出:采集源 → 收集字段 → 记录位置 → **变更后易漏项**。
> 所有投影共享同一安全模型(见 `COLLECTION_SPEC.md` R 节):per-field allowlist、未知字段只记名字(`unprojected_keys`)、credential 只留环境变量名或 `credential_configured: true`、URL 去 userinfo/query、敏感文件只记 path+exists。

### 4.1 Codex(CLI 与 Desktop 共用一份配置)——最常见的变更入口

- **采集源**:`%USERPROFILE%\.codex\config.toml`(CLI 与桌面端共用,`CODEX_HOME` 指向同一目录;桌面端设置界面的修改直接落在这个文件)。`auth.json` 只记存在,永不读内容。
- **收集字段**(顶层标量 allowlist):`model`、`sandbox_mode`、`model_reasoning_effort`、`model_context_window`、`model_auto_compact_token_limit`。未知顶层键按名记入 `unprojected_keys`;`[mcp_servers.*]` 表**不进 profile**,归 MCP inventory。
- **记录位置**:profile → `context/configs/ai/codex-cli.json`;MCP → `context/configs/mcp.json`(tool=codex-cli);两个实体 → `context/software/ai.json`(`codex-cli` 由命令探测、`codex-desktop` 由 host-authoritative provider 刷新版本化包路径)。
- **变更后易漏项**:
  - 用户在桌面端改"上下文/模型"设置 = 改了 config.toml → 跑一次 sync 即可,检查 profile 五项是否更新;
  - 新增 MCP server 会同时出现在 config.toml 的表里和 mcp.json 里,两处都要在 diff 里确认;
  - Codex Desktop 自动升级后版本化目录变化由 routine provider 自动跟随,无需手工。

### 4.2 OMP(Oh My Pi)

- **采集源**:`%USERPROFILE%\.omp\agent\config.yml`(shell、默认思考档、模型角色、搜索顺序)+ `models.yml`(provider 与模型目录)。不透明文件:`.env`、`agent.db`(认证状态)、`history.db`(会话历史)只记 path+exists,**永不读取**。
- **收集字段**:
  - config.yml:`shellPath`、`defaultThinkingLevel`、`modelRoles`(名→标量)、`providers.webSearchOrder`(标量序列);
  - models.yml 每个 provider:`api`、`authHeader`、`baseUrl`(safe-url)、`apiKey`/`apiKeyEnv`→`credentialEnvName`、`models[]` 的 `id/name/reasoning/input/tokenizer/supportsTools/contextWindow/maxTokens` + `thinking{mode,efforts,defaultLevel,requiresEffort}` + `compat{supportsReasoningEffort}`、`modelOverrides`(同模型 allowlist)。
- **记录位置**:profile → `context/configs/ai/omp.json`(`credential_env_names` 汇总环境变量名);实体 → `context/software/ai.json`(`install.root` 每次从解析到的 executable 自动推导;`curated.notes` 记录版本钉住策略)。
- **变更后易漏项**:
  - models.yml 新加 provider → sync 自动投影;**检查 `unprojected_keys` 是否出现意料外字段名**(说明源里有 allowlist 外的东西,需评估是否扩 allowlist);
  - 新增 `compat`/`thinking` 子字段需要显式扩 allowlist(嵌套 object schema 是 mapping-only,未知形状会被拒并记 redaction);
  - OMP 版本有意钉在 18.0.6,**不要执行 `omp update`**;
  - OMP 无文件级 MCP 配置,mcp.json 的 `unresolved` 说明是预期状态。

### 4.3 DSH

- **采集源**:`%USERPROFILE%\.dsh\settings.yaml`。`.credentials.yaml` 只记存在;`.agent-presets` 目录记预设名与路径。
- **收集字段**:`llm-*` 段的 providers(`displayName`、`apiKeyEnv`/`apiKey`→`credentialEnvName`、`api`、`baseURL`(safe-url)、`defaultInput`、`defaultMaxTokens`、`models[]` 含 `reasoningEfforts`(effort→effort 映射));`agent-default-model`;`agent-presets`(名→标量)。
- **记录位置**:`context/configs/ai/dsh.json`;实体在 `software/ai.json`(命令探测)。
- **变更后易漏项**:provider 既可能是 `llm-x.providers.*` 形状也可能是 `llm-x` 直接带 `baseURL` 的形状,两种都会被投影;非 llm 段(如 `ui-theme`)不收。

### 4.4 ZCode

- **采集源**:`D:\ZCode\appdata\.zcode\v2\config.json`(**唯一 active 源**)。`%USERPROFILE%\.zcode\v2` 下的旧副本**永不解析、永不晋升**,只记 path+exists(role=`sensitive-config-copy`);`credentials.json` 只记存在。
- **收集字段**:每个 provider 的 `name/kind/enabled/source`、`options.baseURL`(safe-url)、`options.apiKey`→`credential_configured: true`、`models{name, reasoning, limit, modalities}`;`setting.json` 的三个选择键;`bot-config.json` 的 bots 列表。
- **记录位置**:`context/configs/ai/zcode.json`;实体在 `software/ai.json`。
- **变更后易漏项**:新增 provider 的 API key **永远只出现为 `credential_configured: true`**,diff 里看到这个布尔属预期;如果 diff 里出现任何 key 值形状,立即停下排查。

### 4.5 OpenCodex

- **采集源**:`%USERPROFILE%\.opencodex\config.json`。`auth.json`、`codex-accounts.json`、`admin-api-token`、`usage.jsonl`、`routing-history.sqlite` 只记存在。
- **收集字段**:顶层(`port`、`defaultProvider`、`contextCapValue`、`providerContextCaps`、`clientIntegrations`、`websockets`、`codexAutoStart`、`subagentModels`、`disabledModels`);每个 provider 的 adapter/网络/模型维度字段 + `modelContextWindows`/`modelReasoningEfforts`/`modelReasoningEffortMap`(严格标量叶映射)+ `apiKey`/`apiKeyPool`/`apiKeys`→`credential_configured: true`;`claudeCode{enabled,authMode,desktopProfile.defaults}`;`webSearchSidecar`/`visionSidecar`。
- **记录位置**:`context/configs/ai/opencodex.json`;实体在 `software/ai.json`。
- **变更后易漏项**:DSH 等下游依赖 OpenCodex 时,`context/configs/ai/` 两个 profile 的 diff 要一起看;`modelReasoningEffortMap` 值里出现嵌套 object 会被拒(记 `unsupported-value` redaction),属预期防护。

### 4.6 Qoder CN(桌面端 agent)

- **现状**:用户**实际使用的是桌面端 agent**;安装器附带的 `qoderclicn` CLI 与 `qodersec` 组件存在但**不使用**(2026-08 用户确认,已写入 curated)。
- **采集源**:
  - profile:`%USERPROFILE%\.qoder-cn\settings.json`(安全用户状态);
  - **`%USERPROFILE%\.qoder-cn\mcp-router.json` 含运行时 API key,只记 path+exists,内容永不读取**;
  - 实体:HKCU 卸载项 `f160a86b-5726-553b-9fff-d78743c4373f` + `D:\Qoder-CN\Qoder CN`;
  - 捆绑组件:`%USERPROFILE%\.qodersec`(只做路径观察)。
- **收集字段**:profile 投影 `enabledPlugins`(插件名→bool);未知顶层键按名记入 `unprojected_keys`(如 `mcpServers`——它归 MCP inventory);实体为 `present/version/executable/install_location` + registry-uninstall/user-confirmed evidence。
- **记录位置**:profile → `context/configs/ai/qoder.json`;MCP → `context/configs/mcp.json`(tool=qoder,读 settings.json 的 `mcpServers`,多余字段如 `qoder_url` 不读);实体 → `context/software/ai.json`。
- **变更后易漏项**:改插件开关 → profile diff;加/改 MCP server → mcp.json diff;升级 Qoder → 注册表 DisplayVersion 变化需按 §8 手工刷新实体;若开始实际使用 CLI,按 §7 给它建实体。

### 4.7 MCP 跨工具清单

- **采集源**(五个):`%USERPROFILE%\.claude.json`、`%USERPROFILE%\.gemini\settings.json`、`%USERPROFILE%\.codex\config.toml`(`[mcp_servers.*]` 表)、`%USERPROFILE%\.cursor\mcp.json`、`%USERPROFILE%\.qoder-cn\settings.json`(`mcpServers` 键;运行时 `mcp-router.json` 含 API key,永不读取)。
- **收集字段**:`tool/scope/name/transport`、`command`(归一化)、`url`(safe-url)、`args`(**按序列检查**:credential 类 flag(`--token`、`--api-key`、`-H`/`--header` 等)连同它消费的下一个 argv 一起丢弃;`flag=value` 形式单独丢弃)、`env` 只存变量名。
- **记录位置**:`context/configs/mcp.json`;无文件级 MCP 的工具在 `unresolved` 中说明。
- **变更后易漏项**:新工具若也有 MCP 配置文件,需要给 collector 增加对应源(参考 §7 checklist);diff 里 `redactions` 出现 `unsafe-argument`/`credential-argument` 属预期防护。

## 5. 普通软件 / 小工具(简)

- **去哪收集**:HKCU/HKLM 卸载表(routine 候选)、安装目录存在性、`--version`(若有 CLI)。
- **收集哪些**:name、version、publisher、归一化 install_location、必要时一条 `purpose`。**不收**:Redistributable/driver/系统组件、游戏、每个补丁版本。
- **记录到哪**:按用途分域 → `context/software/creative.json`、`productivity.json` 等(新域 = 新文件 + index 登记);开发相关进 `development.json`/`ai.json`。
- **易漏项**:MSIX 商店应用自动升级会使版本化路径过期(见 §8);候选 ≠ 事实,晋级 canonical 需要确认。

## 6. 语义与 curated 更新(用户确认类信息)

- 触发:用途、角色、状态、使用关系、"实际在用哪个"等脚本无法检测的语义变化;以及**补充实体的添加/刷新**(新装的桌面 app、升级后的版本刷新——canonical 里没有 routine provider 覆盖它们,见 §8)。
- 流程(二选一):
  1. **对话确认 + 一次性修正脚本**(当前实际用法):在 `.local/` 写临时脚本,用仓库 lib(`Read-McJson`/`Set-McObjectProperty`/`Write-McJson`)精确修改目标字段或添加实体,运行后删除或在说明中标注一次性;适用单点修正与实体添加(qoder/workbuddy/claude-desktop 刷新都是先例,脚本留在 `.local/` 可复用);
  2. **`curate.ps1` confirmation manifest**(批量/可审计):手写确认 manifest(形状见 `docs/examples/curate-confirmation.example.json`;`evidence_refs` 必须能在 `.local/g2-semantic-review.json` 里找到),默认 dry-run 生成 plan,显式 `-Apply` 才生效;manifest 里出现 `observed` 字段、未知 ID、非法证据会直接拒绝。
- **易漏项**:
  - `evidence` 数组**只增不减**(按 JSON 全等去重):改 evidence 形状后旧的会在 canonical 里残留,必须做一次性清理,否则二次 sync 不幂等;
  - 删除实体/记录属于显式清理(removal policy),reconciliation 不会自动删除;
  - 语义必须能追溯到 observed 证据,不得凭空推断。

## 7. 新增采集项 / 新工具 checklist

0. **定位新工具的配置位置**(用户说"装了/改了 X"但 §4 没有它时):依次检查 `%USERPROFILE%` 下的点目录(`ls -dt ~/$HOME.[a-z]*` 按修改时间排)、`%APPDATA%`/`%LOCALAPPDATA%`、安装目录、注册表卸载项(HKCU/HKLM/WOW6432Node Uninstall);参考 qoder(`.qoder-cn`)与 workbuddy(`.workbuddy`)案例;
1. 读 `docs/COLLECTION_SPEC.md` 确认该信息的长期价值与隐私边界(`PRIVACY.md`);
2. 加采集能力:新 collector 或 ai-tools/配置投影定义——**只读、fail-soft、有超时**;能探测到的最小安全字段集;**先看文件里有什么再定 allowlist**,发现 credential 形状内容时该文件整体降级为"只记存在";
3. fixture + 测试:真实源文件形状的 fixture、泄漏反例(假 secret 值不得出现在投影)、序列化确定性;
4. 更新 `COLLECTION_SPEC.md`(新类别先改 spec 再采集)与 `SCHEMA.md`(若新增字段/记录形状);
5. 跑 §2.3 全部 gate;
6. devlog 记录本次变更(参考既有案例:`docs/devlog/2026-08-28-ai-config-inventory.md`(全新 configs 模块)、`2026-08-29-qoder-and-codex-cli-profile.md`(新工具+新 profile)、`2026-08-29-qoder-desktop-clarification.md`(实体归属纠正)、`2026-08-29-cold-start-sync-gaps.md`(新 agent 入库+配置 profile 补漏));
7. 分块提交并推送(§2.4)。

## 8. 已知限制与全局易漏项

- **补充桌面实体会静默过期**:qoder、trae、workbuddy、antigravity 等桌面 app 的实体由 registry/文件系统证据一次性记录,**routine scan 不刷新它们**。用户报告升级后,按注册表 `DisplayVersion` 用一次性脚本刷新 `observed.version`(trae 0.1.39→0.1.58 即为此修复);MSIX 商店应用(claude-desktop)同理且路径也会变:

  ```powershell
  $package = Get-AppxPackage -Name 'Claude'
  # 更新 observed.version / executable / install_location / package_full_name
  # 注意:WindowsApps 受 ACL 保护,Test-Path 对包内文件返回 False 是正常的,
  # 以 Get-AppxPackage 的 InstallLocation/AppxManifest 为准。
  ```

  **数据核对时的教训(2026-08-29)**:只验证"路径存在性"查不出这类过期——trae 的 exe 路径一直有效,版本却落后了一个。核对补充桌面实体必须**把注册表 `DisplayVersion` 与 canonical `observed.version` 全量比对一遍**(qoder/trae/workbuddy/antigravity 等),不能只查路径。

- **CURRENT.md 是生成物**:手改会被下次渲染覆盖;要改内容改 canonical 或渲染器。
- **`unprojected_keys` / `redactions` 是信息不是错误**:出现新条目时先判断是"源里多了东西"还是"allowlist 缺口",在 devlog 里说明处理决定。
- **stale 语义**:只有**确认源文件不存在**才把 profile 标 `source_state: stale`;解析失败保留旧记录不动。反过来,一个实体"本次扫描没出现"不等于被卸载。
- **不采集清单**见 `PRIVACY.md`(never-collect);遇到任何拿不准的敏感内容,默认不收,先问用户。qoder 的 `mcp-router.json`(运行时 API key)就是"只记存在"的现成例子。
