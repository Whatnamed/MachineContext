# MachineContext Roadmap

The roadmap is intentionally staged. Later phases should be pulled forward only when the previous maintenance loop is reliable.

## Phase 0 — Repository bootstrap and design convergence

Status: complete.

- private GitHub repository;
- canonical JSON context layout + `CURRENT.md` entry view;
- privacy/schema/agent rules;
- product/development/collection documentation;
- similar-project and Windows inventory research;
- layered discovery/reconciliation design;
- implementation guardrails for observed/curated ownership, provider health, atomic publication, and Git sync;
- initial script/collector/test folders.

## Phase 1 — Initial Audit, V1 Simplification, and Integration

Status: complete.

Goal: turn the repository from a documented skeleton into verified context for the real Windows machine, simplified for immediate AI consumption.

Delivered:

- shared PowerShell probe/JSON/path/privacy/staging helpers;
- structured Windows providers (Registry/CIM/PATH/tool-specific APIs/CLIs/deduped verifiers);
- Quick / Discover / Enrich / Full modes;
- optional Everything indexed discovery adapter + bounded fallback;
- project fingerprint discovery;
- candidate/evidence reconciliation and stable identity;
- multi-source dedupe and safe absence semantics;
- canonical `observed` updates preserving `curated` semantics without redundant status boilerplate;
- provider health/diagnostics and compact `context/status.json`;
- privacy/reference validation;
- deterministic compact `CURRENT.md` rendering;
- atomic staging/publication and safe `sync.ps1` orchestration;
- real-machine Full Audit and broad inventory integration (`creative.json`, `productivity.json`, and supplemental tool provenance);
- long-lived project registry with confirmed purposes and refined directory roles / drive tendencies;
- idempotence, verification, and regression tests.

## Phase 2 — Normal Use and Routine Maintenance

Status: active baseline (V1 feature-frozen).

Goal: use MachineContext in everyday pairing without ongoing architectural rework.

Operational baseline:

- routine core updates run via `Quick` / `Full` sync;
- supplemental inventories (`creative.json`, `productivity.json`, and broad inventory tools) are refreshed explicitly via manual broad scans;
- no-change scans maintain zero semantic diff;
- changes are driven by concrete machine modifications or planning needs rather than perpetual self-refactoring.

## Phase 3 — Extended Software Domains

Status: partially integrated ahead of schedule into V1.

Selective creative (`creative.json`) and productivity (`productivity.json`) inventories have been confirmed and included with clear `manual-broad-scan` provenance. Further domain expansions (such as `browsers.json` or `media.json`) are deferred until specific planning tasks require them.

## Phase 4 — Convenience CLI / optional read-only MCP

Goal: reduce user/agent friction without changing the canonical model.

Potential CLI:

- `mc scan [quick|discover|full]`
- `mc verify`
- `mc status`
- `mc sync`
- `mc project add`

If local Agent usage shows clear benefit, expose a small read-only MCP over the same canonical/live context. Neither CLI nor MCP becomes a new source of truth.

## Phase 5 — Smarter planning support

Potential features:

- impact analysis before moving/upgrading a tool;
- installation-location recommendations based on real conventions, disk roles, managers, and downstream relationships;
- update-path recommendations based on original install/manager ownership;
- change summaries optimized for web AI;
- targeted refresh of only the context required by the current planning task;
- optional scheduled verification if it proves useful.

## Optional future — Local dashboard / deeper scopes / multi-machine

A dashboard is only justified if files + CLI becomes inconvenient for browsing/maintenance. Deeper WSL/container inventory and multi-machine support are deferred until actual usage requires them.

Any future UI/database may cache/index canonical data, but readable portable repository files remain the authoritative exchange layer.
