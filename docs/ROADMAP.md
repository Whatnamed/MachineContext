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

## Phase 1 — Initial Audit + V1 collector

Status: next.

Goal: turn the repository from a documented skeleton into verified context for the real Windows machine.

Deliverables:

- shared PowerShell probe/JSON/path/privacy/staging helpers;
- structured Windows providers (Registry/CIM/PATH/tool-specific APIs/CLIs);
- Quick / Discover / Enrich / Full modes;
- optional Everything indexed discovery adapter + bounded fallback;
- project fingerprint discovery;
- candidate/evidence reconciliation and stable identity;
- multi-source dedupe and safe absence semantics;
- canonical `observed` updates preserving `curated` semantics;
- provider health/diagnostics and compact `context/status.json`;
- privacy/reference validation;
- deterministic `CURRENT.md` rendering;
- atomic staging/publication and safe `sync.ps1` orchestration;
- first real-machine Full Audit using `BOOTSTRAP_HINTS.md` only as search hints;
- initial long-lived project registry and installation conventions;
- idempotence/recovery tests.

## Phase 2 — Maintenance hardening

Goal: make routine updates boring and dependable.

Possible work:

- targeted scope refresh based on changed/related entities;
- stronger installer/update ownership inference;
- better conflict resolution and diagnostics;
- broader fixture coverage for localized/edge-case Windows outputs;
- stale/freshness policies by provider/domain where useful;
- explicit reviewed commit/push helper;
- relationship consistency and impact checks;
- performance profiling/bounded concurrency based on real scan timings.

## Phase 3 — General software context

Goal: expand beyond development only after the core loop is trustworthy.

Add selective modules such as:

- `general.json` — common desktop utilities;
- `creative.json` — design/Adobe/3D/CAD/image/video tools;
- `productivity.json` — notes/sync/Office-like tools;
- `browsers.json` — profile-independent browser facts;
- `media.json` — only when useful for planning.

Broad Windows installed-app inventory can feed candidates, but persistent context remains decision-oriented rather than becoming an enterprise CMDB.

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
