# Documentation

This directory describes MachineContext itself. Machine facts belong under `context/`; project documentation belongs here.

## Core documents

- `PRODUCT.md` — problem, product goals, quality attributes, scope, and future direction.
- `ARCHITECTURE.md` — repository layers, source-of-truth boundaries, evidence flow, and publication model.
- `DEVELOPMENT.md` — current implementation phase, workflow, and acceptance criteria.
- `COLLECTION_SPEC.md` — authoritative V1 list of **what information is worth collecting**.
- `DISCOVERY_DESIGN.md` — **how to discover unknown/forgotten tools and projects**, reconcile evidence, and avoid brute-force crawling.
- `IMPLEMENTATION_GUIDE.md` — concrete Windows-first implementation guardrails, data ownership, sync, privacy, tests, and edge cases.
- `REFERENCE_RESEARCH.md` — similar projects/tools reviewed and the adopt/adapt/reject decisions derived from them.
- `BOOTSTRAP_HINTS.md` — historical machine/project clues from earlier sessions; useful only for locating facts during the first audit and never canonical by themselves.
- `ROADMAP.md` — staged development direction after V1.
- `DECISIONS.md` — durable architecture and data-model decisions.
- `devlog/` — concise chronological implementation notes.

Root-level policy/reference documents remain `AGENTS.md`, `PRIVACY.md`, `SCHEMA.md`, and `CHANGELOG.md`.

## Document ownership

`AGENTS.md` contains repository-wide instructions/invariants only. It must not become a task plan.

`CURRENT.md` is the generated compact machine-context entry point for AI consumers. It is not project-development documentation or independent truth.

`COLLECTION_SPEC.md` is the persistent collection-value contract; `DISCOVERY_DESIGN.md` is the persistent discovery/reconciliation contract. Do not rely on a one-off prompt to reconstruct either.

When a durable requirement changes, update the relevant document here rather than depending on a future chat to reconstruct it.
