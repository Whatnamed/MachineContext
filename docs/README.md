# Documentation

This directory describes MachineContext itself. Machine facts belong under `context/`; project documentation belongs here.

## Core documents

- `PRODUCT.md` — problem, product goals, quality attributes, scope, and future direction.
- `ARCHITECTURE.md` — repository layers, source-of-truth boundaries, and data flow.
- `DEVELOPMENT.md` — current implementation phase, workflow, and acceptance criteria.
- `COLLECTION-SPEC.md` — authoritative V1 list of what the local collector should detect and how records should be represented.
- `INITIAL-AUDIT.md` — first-machine-audit plan plus historical hints that must be verified locally.
- `ROADMAP.md` — staged development direction after V1.
- `DECISIONS.md` — durable architecture and data-model decisions.
- `devlog/` — concise chronological implementation notes.

## Document ownership

`AGENTS.md` contains only repository-wide instructions for agents. It should not become a task plan.

`CURRENT.md` is the compact machine-context entry point for AI consumers. It should not become project-development documentation.

When a durable requirement changes, update the relevant document here rather than depending on a future prompt to reconstruct it.
