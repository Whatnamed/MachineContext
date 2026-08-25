# MachineContext

MachineContext is a private, AI-readable source of truth for this computer's environment.

Its purpose is to let ChatGPT, Codex, Agy, and other agents quickly understand the real machine before planning installations, development work, configuration changes, upgrades, or troubleshooting.

## Design goals

MachineContext should remain:

- maintainable: objective facts should be re-detectable instead of manually copied forever;
- fast to read: start from `CURRENT.md`, then open only the relevant canonical files;
- complete enough for decisions: versions, paths, install/update methods, roles, constraints, projects, and important relationships;
- current: detected facts carry verification state and time;
- lightweight: do not mirror lockfiles, complete installed-app databases, logs, caches, or secrets;
- extensible: new software domains and projects should be addable without reorganizing the repository.

## Read order

For an AI planning a machine-dependent task:

1. Read `CURRENT.md`.
2. Read `machine-context.yaml` to locate canonical sources.
3. Open only the relevant files under `context/`.
4. For a specific development project, read its MachineContext project record and then the project's own repository manifests if deeper dependency detail is required.

`CURRENT.md` is a convenience view. Canonical YAML under `context/` wins if there is a conflict.

For an agent developing MachineContext itself, read `AGENTS.md` and then `docs/DEVELOPMENT.md`.

## Documentation

Start with `docs/README.md`. The main documents are:

- `docs/PRODUCT.md` — product purpose, principles, scope, non-goals, and future directions;
- `docs/ARCHITECTURE.md` — source-of-truth boundaries and data flow;
- `docs/DEVELOPMENT.md` — active implementation phase and V1 acceptance criteria;
- `docs/COLLECTION_SPEC.md` — authoritative list of what the local audit/collector should collect;
- `docs/BOOTSTRAP_HINTS.md` — historical, unverified clues used only to locate facts during the first audit;
- `docs/ROADMAP.md` — staged future development;
- `docs/DECISIONS.md` — durable architecture/data-model decisions;
- `docs/devlog/` — concise cross-session development notes;
- `SCHEMA.md` — lightweight data-model conventions;
- `PRIVACY.md` — collection and secret-handling boundaries;
- `CHANGELOG.md` — notable project-level changes.

## Repository layout

```text
MachineContext/
  CURRENT.md
  machine-context.yaml
  AGENTS.md
  PRIVACY.md
  SCHEMA.md
  CHANGELOG.md
  docs/
    devlog/
  context/
    machine.yaml
    network.yaml
    conventions.yaml
    relationships.yaml
    software/
    projects/
  scripts/
    collect.ps1
    verify.ps1
    render.ps1
    validate.ps1
    sync.ps1
    collectors/
    lib/
  tests/
    fixtures/
  schemas/
```

## V1 scope

The first version focuses on machine/system facts, development runtimes and package managers, SDK/toolchains, AI coding tools, relevant network/local services, long-lived local projects, installation/update conventions, useful relationships, and privacy-safe verification.

General non-development software can be added later as separate software modules without changing the core model.

## Maintenance model

Target flow:

`scan -> verify -> privacy check -> update canonical context -> render CURRENT.md -> review diff -> commit/push`

The repository intentionally starts with files and small local scripts. A CLI or UI should only be added when it clearly reduces real maintenance cost.

## Repository visibility

This repository is intended to remain **private**. It still must never contain secrets. See `PRIVACY.md`.
