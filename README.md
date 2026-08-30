# MachineContext

MachineContext is a private, AI-readable source of truth for this computer's environment.

Its purpose is to let ChatGPT, Codex, Agy, and other agents quickly understand the real machine before planning installations, development work, configuration changes, upgrades, migrations, or troubleshooting.

## Design goals

MachineContext should remain:

- maintainable: objective facts are re-detectable and semantic context has clear ownership;
- fast to read: start from `CURRENT.md`, then open only relevant canonical files;
- complete enough for decisions: versions, paths, install/update methods, roles, constraints, projects, and useful relationships;
- current and verifiable: discovery evidence and provider health prevent stale/partial scans from masquerading as truth;
- lightweight: no database/GUI/raw full-disk dump is required for V1;
- extensible: new software domains, providers, projects, and future environment scopes are additive.

## Read order

For an AI planning a machine-dependent task:

1. Read `CURRENT.md`.
2. Read `machine-context.json` to locate canonical sources.
3. Open only the relevant JSON files under `context/`.
4. For a specific project, use its MachineContext record to locate the project's own manifests/repository when deeper dependency detail is required.

`CURRENT.md` is generated convenience context. Canonical JSON under `context/` wins on conflict.

For an agent developing MachineContext itself, read `AGENTS.md` and `docs/DEVELOPMENT.md` first.

## Documentation

Start with `docs/README.md`.

- `docs/PRODUCT.md` — product purpose, principles, scope, non-goals, and future direction;
- `docs/ARCHITECTURE.md` — source-of-truth boundaries and data flow;
- `docs/DEVELOPMENT.md` — active V1 implementation phase and acceptance criteria;
- `docs/COLLECTION_SPEC.md` — authoritative list of information worth collecting;
- `docs/DISCOVERY_DESIGN.md` — how unknown tools/projects are discovered and reconciled;
- `docs/IMPLEMENTATION_GUIDE.md` — concrete V1 implementation guardrails and edge cases;
- `docs/REFERENCE_RESEARCH.md` — research on similar projects/tools and adopt/adapt/reject conclusions;
- `docs/BOOTSTRAP_HINTS.md` — historical, unverified clues used only during the first audit;
- `docs/ROADMAP.md` / `docs/DECISIONS.md` / `docs/devlog/` — future phases, durable decisions, and session notes;
- `SCHEMA.md` / `PRIVACY.md` — data contract and privacy boundaries.

## Repository layout

```text
MachineContext/
  CURRENT.md
  machine-context.json
  AGENTS.md
  PRIVACY.md
  SCHEMA.md
  docs/
  context/
    status.json
    machine.json
    network.json
    conventions.json
    relationships.json
    software/
    projects/
    configs/
  scripts/
    collect.ps1
    verify.ps1
    render.ps1
    validate.ps1
    sync.ps1
    audit.ps1
    review.ps1
    curate.ps1
    collectors/
    lib/
  tests/
    fixtures/
  schemas/
```

Ignored `.local/` is reserved for staging, raw candidates, exact check timestamps, and diagnostics that must not be committed.

## V1 collection model

Routine maintenance uses a layered pipeline instead of either a checklist-only scan or brute-force full-disk crawl:

`structured sources -> discovery candidates -> evidence reconciliation -> verification -> canonical JSON -> CURRENT.md`

Scan profiles are `Quick`, `Discover`, `Enrich`, and `Full` (Initial Audit). Everything/`es.exe` may be used as an optional indexed discovery accelerator when already installed; it is never required or auto-installed.

## Maintenance model

Target flow:

`collect -> reconcile/verify -> validate/privacy -> render -> atomic publish -> git diff -> review -> commit/push`

The repository intentionally starts with files and small Windows-first local scripts. A CLI, MCP, UI, database, daemon, or multi-machine layer should only be added when real use demonstrates a problem it solves.

## Repository visibility

This repository is intended to remain **private**. It still must never contain secrets. See `PRIVACY.md`.
