# MachineContext Architecture

## Architecture summary

MachineContext uses a files-first architecture with four layers:

1. **Canonical context** — structured machine facts under `context/`.
2. **AI entry view** — `CURRENT.md`, a short rendered summary for fast consumption.
3. **Maintenance tooling** — local, deterministic scripts under `scripts/` that collect, verify, validate, render, and synchronize context.
4. **Project documentation** — `docs/`, which describes MachineContext itself rather than the user's machine.

Git provides history and GitHub provides private remote sharing between local and web AI.

## Source-of-truth boundaries

### Canonical facts

`context/` owns current machine context:

- `machine.yaml` — OS, hardware, storage, shells, important paths, environment constraints;
- `network.yaml` — proxy/network context and approved local services;
- `conventions.yaml` — installation, location, and update conventions;
- `relationships.yaml` — useful cross-tool/project relationships;
- `software/` — modular software domains;
- `projects/` — environment-level records for long-lived local projects.

### Generated view

`CURRENT.md` is optimized for reading speed. It should be generated from canonical context and should not become a second independently edited truth store.

### External project truth

Detailed project dependencies remain in each project's own repository manifests and lockfiles. MachineContext stores only enough project context to locate and reason about those sources.

## Data flow

```text
real Windows machine
      |
      v
read-only collectors
      |
      v
normalized detected facts
      |
      +--> verification / reconciliation
      |       |
      |       +--> semantic roles, conventions, relationships
      v
canonical context/*.yaml
      |
      +--> validation + privacy checks
      |
      +--> render CURRENT.md
      v
git diff -> review -> commit/push
      |
      v
private GitHub repository
      |
      +--> web ChatGPT reads CURRENT.md first
      +--> local agents read canonical files as needed
```

## Collector design

Collectors should be small, domain-specific, read-only, and fail-soft. System calls and parsing/normalization should be separable so the normalization layer can be tested with fixtures.

A missing executable, non-default path, permission failure, or unavailable subsystem is normal input, not a fatal scan condition.

Collectors should return structured facts rather than write arbitrary Markdown reports.

## Verification model

Volatile facts should carry enough metadata to answer:

- where did this value come from;
- when was it observed;
- can it be verified again;
- is it still current.

Typical verification states are `verified`, `stale`, `pending`, and `unavailable`. Typical sources are `detected`, `manual`, `imported`, and `inferred`.

Semantic fields such as `primary`, `legacy`, project status, or a preferred installation root are not always objectively detectable. They may be maintained by the user/agent but should be based on observed reality.

## Extensibility

The architecture favors additive modules. New software domains should be added under `context/software/` and registered in its index. New projects should be individual records under `context/projects/`.

Do not solve growth by making `machine.yaml` or one software file a giant catch-all.

The root `machine-context.yaml` manifest exists so consumers can discover canonical modules without hard-coding every future path.

## Why no database or GUI in V1

The expected dataset is small, highly inspectable, and naturally suited to versioned text files. YAML/Markdown plus Git gives direct AI readability, auditability, portability, and low maintenance cost.

A CLI may later wrap common commands. A GUI or local database is justified only if real use shows that the file/script model is no longer convenient enough. Even then, human/AI-readable canonical export should remain a core property.
