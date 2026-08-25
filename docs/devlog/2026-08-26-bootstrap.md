# 2026-08-26 — Repository bootstrap

## Scope

Established the initial MachineContext repository structure and prepared it for the first local-machine implementation pass.

## Decisions and structure

- Chose a files-first, private GitHub repository as the shared machine-context layer.
- Separated canonical machine facts (`context/`) from project documentation (`docs/`) and the fast AI entry view (`CURRENT.md`).
- Added modular software and project registries so future categories can grow additively.
- Added a formal collection specification instead of relying on a future prompt to tell the local agent what to inspect.
- Preserved old conversation-derived machine information only as unverified bootstrap hints, not canonical truth.
- Kept `AGENTS.md` focused on global agent constraints rather than embedding the active implementation task.
- Defined V1 as read-only collection, normalization, verification, privacy validation, rendering, and a simple sync workflow.

## Current state

The repository is still in bootstrap state. Canonical context contains placeholders and must not be treated as a complete representation of the real machine.

The next implementation session should perform the first local read-only audit and build the V1 collector/verification pipeline described in `docs/DEVELOPMENT.md` and `docs/COLLECTION_SPEC.md`.

## Important guardrail

Historical versions and paths in `docs/BOOTSTRAP_HINTS.md` are search hints only. They must be re-detected locally before being promoted into `context/`.
