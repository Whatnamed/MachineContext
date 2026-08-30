# MachineContext 开发计划

## 当前阶段

当前处于 **V1 Feature-Frozen for normal use(日常实机使用基线)**。

- 核心开发环境、AI/Agent 体系、创意设计与生产力工具已完成全量实机核验并结构化入库;
- routine core scan 与 supplemental user-confirmed broad inventory 的来源边界已明确;
- `CURRENT.md` 已收敛为紧凑、高信号的 AI 快速入口;
- 阶段性构建历史(Phase A–G2)已归档至 `docs/devlog/2026-08-26-v1-build-phases.md`。

### 冻结期允许的变更

- **允许**:additive 变更——新增采集项、新增 provider/工具定义、新增配置 profile、新增 software domain、fixture/测试与对应文档;走 `docs/OPERATIONS.md` §7 的 checklist。
- **不允许**:架构性重构(数据模型、identity model、目录结构、发布流程);此类需求先写入 `docs/ROADMAP.md` 与 `docs/DECISIONS.md` 重新评估。
- 不确定某变更属于哪类时,先在 devlog 里写清理由再动手。

## 开始实现前必须阅读

1. `AGENTS.md`
2. `docs/OPERATIONS.md`(运行任何采集/同步/发布前)
3. `docs/COLLECTION_SPEC.md`
4. `docs/DISCOVERY_DESIGN.md`
5. `docs/IMPLEMENTATION_GUIDE.md`
6. `PRIVACY.md`
7. `SCHEMA.md`
8. `docs/BOOTSTRAP_HINTS.md`(仅作为历史查找线索)

## V1 交付目标

V1 完成时应满足:

1. 安全、只读地采集 Collection Spec 中 V1 必需事实;
2. 不只查已知工具,还能通过 Discover/Full 模式发现用户忘记的项目、portable/custom-install 工具和安装来源;
3. Discovery candidate 经过 evidence reconciliation + verifier 后才能成为 canonical fact;
4. canonical context 使用 JSON,并区分 collector-owned `observed` 与 user/agent-owned `curated`;
5. provider health 能区分 `success / partial / unavailable / timed_out / failed`,失败不能误判软件被卸载;
6. `CURRENT.md` 从 canonical data 生成,短、稳定、适合网页 AI 快读;
7. push 前完成 schema/reference/privacy validation,raw discovery 不进入 Git;
8. 同步流程使用 staging + atomic publication,失败不能留下半更新状态;
9. 同一真实实体来自 Registry/winget/PATH/filesystem 等多个 source 时能正确去重;
10. 项目 registry 只保存环境级 context,不复制项目完整依赖;
11. 初次审计后形成真实安装/更新目录习惯;
12. 无机器事实变化的重复运行保持零 semantic diff。

## 关键工程要求

- **Read-only**:scan 不改变机器。
- **Fail-soft**:一个 provider 失败不阻塞整个 scan。
- **Timeout**:所有外部 command probe 都有硬超时。
- **Evidence-first**:filesystem hit 不是 truth。
- **Identity-safe**:同一软件多 source 不重复;path move 不轻易变 remove+add。
- **Ownership-safe**:collector 不覆盖 curated fields。
- **Atomic**:validation 失败旧 canonical 保持完整。
- **Idempotent**:no-change scan 零 semantic diff;必要 heartbeat 限于 compact status。
- **Privacy by construction**:parser allowlist 优先于最后 regex redaction。
- **Locale-tolerant**:优先 JSON/API/Registry,文本 parser 必须 fixture test。
- **Unicode-safe**:中文/空格路径必须是一等测试场景。
- **Scope-aware**:Windows/WSL/project-local 环境不能扁平混合。
- **Measured performance**:记录 collector duration,再决定是否并发优化。

## V1 暂不实现

- GUI;
- 常驻 daemon;
- 全量普通软件深度语义化;
- 多机器模型;
- 深入扫描每个 WSL distro;
- 自动安装 Everything/osquery/collector dependencies;
- 自动安装/卸载/升级软件;
- 自动修改 PATH、代理、注册表或系统设置;
- write-enabled MCP;
- 无 review 的自动 force/commit/push。

## V1 验收

完成 Initial Full Audit 后满足:

- 主要开发环境、AI 工具、关键本地服务与长期项目足够完整;
- 已知历史线索都被验证或明确标为不存在/未知;
- Discover 模式能额外发现 checklist 未显式列出的候选;
- 关键版本/path/install/update ownership 可重新验证;
- Registry + winget + command + filesystem 重叠结果正确去重;
- provider failure 测试不会造成虚假 removal;
- 无 secrets/raw full-disk dump;
- 第二次无变化运行只有允许的 compact verification metadata 变化,其他 canonical byte-stable;
- `CURRENT.md` + 少量按需 JSON 足够让网页 GPT 正确理解环境;
- 新增 software module / project / provider 不需要调整核心目录和 identity model。
