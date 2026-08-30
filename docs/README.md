# Documentation

This directory describes MachineContext itself. Machine facts belong under `context/`; project documentation belongs here.

## Core documents

- `OPERATIONS.md` — **operations runbook**: how to collect/record machine changes, the sync/gate/commit/push loop, and per-tool collection playbooks. Start here for any "how do I update/record/sync" question.
- `PRODUCT.md` — problem, product goals, quality attributes, scope, and future direction.
- `ARCHITECTURE.md` — repository layers, source-of-truth boundaries, evidence flow, and publication model.
- `DEVELOPMENT.md` — current implementation phase, freeze policy, and acceptance criteria.
- `COLLECTION_SPEC.md` — authoritative V1 list of **what information is worth collecting**.
- `DISCOVERY_DESIGN.md` — **how to discover unknown/forgotten tools and projects**, reconcile evidence, and avoid brute-force crawling.
- `IMPLEMENTATION_GUIDE.md` — concrete Windows-first implementation guardrails, data ownership, sync, privacy, tests, and edge cases.
- `REFERENCE_RESEARCH.md` — similar projects/tools reviewed and the adopt/adapt/reject decisions derived from them.
- `BOOTSTRAP_HINTS.md` — historical machine/project clues from earlier sessions; useful only for locating facts during the first audit and never canonical by themselves.
- `ROADMAP.md` — staged development direction after V1.
- `DECISIONS.md` — durable architecture and data-model decisions.
- `devlog/` — concise chronological implementation notes, including the archived V1 build-phase history.

Root-level policy/reference documents remain `AGENTS.md`, `PRIVACY.md`, `SCHEMA.md`, and `CHANGELOG.md`.

## Task routing(按任务找文档)

| 我想要… | 看哪里 |
|---|---|
| 了解这台机器的现状 | `CURRENT.md` → `machine-context.json` → 按需 `context/*.json` |
| 机器变了,把记录更新并同步上云 | `docs/OPERATIONS.md` §1–§2(流程/命令/gate/提交推送) |
| 知道某类信息去哪收集、记录到哪 | `docs/OPERATIONS.md` §3(信息地图)与 §4(逐工具详解) |
| 更新用途/状态等语义(curated) | `docs/OPERATIONS.md` §6 |
| 新增采集项 / 新工具 / 新 profile | `docs/OPERATIONS.md` §7 + `COLLECTION_SPEC.md` |
| 判断某信息能不能采集 | `PRIVACY.md` + `COLLECTION_SPEC.md` |
| 理解数据字段与序列化契约 | `SCHEMA.md` |
| 理解发现/对账机制 | `docs/DISCOVERY_DESIGN.md` |
| 了解为什么这样设计 | `docs/DECISIONS.md` + `docs/ARCHITECTURE.md` |
| 了解某次变更的来龙去脉 | `docs/devlog/` |

## Document ownership

`AGENTS.md` contains repository-wide instructions/invariants only. It must not become a task plan or an operations manual (see `OPERATIONS.md`).

`CURRENT.md` is the generated compact machine-context entry point for AI consumers. It is not project-development documentation or independent truth.

`COLLECTION_SPEC.md` is the persistent collection-value contract; `DISCOVERY_DESIGN.md` is the persistent discovery/reconciliation contract; `OPERATIONS.md` is the persistent operations contract. Do not rely on a one-off prompt to reconstruct any of them.

When a durable requirement changes, update the relevant document here rather than depending on a future chat to reconstruct it.
