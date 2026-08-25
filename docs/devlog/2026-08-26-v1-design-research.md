# 2026-08-26 — V1 design research

## Goal

Reduce the chance of implementing the first local collector in a way that later requires structural rework.

## Research

Reviewed adjacent approaches including IO Inventory, DevEnvInfoServer/system_information_mcp, envinfo-style diagnostics, Windows Registry/winget inventory, osquery, and Everything indexed filesystem discovery. Inspected IO Inventory collector/model/settings/snapshot/database patterns and DevEnvInfoServer implementation details rather than relying only on README feature lists.

## Decisions

- Do not fork/vendor an existing inventory application as MachineContext core.
- Borrow modular collectors, provider diagnostics, timeouts, stable identity, fast/enrich separation, and read-only agent principles.
- Add layered unknown discovery instead of depending only on a named checklist.
- Treat broad discovery hits as candidates/evidence, not facts.
- Use Registry + winget enrichment for Windows app inventory; prohibit Win32_Product routine scans.
- Support Everything/ES only as an optional already-installed discovery accelerator.
- Separate observed machine facts from curated user/agent semantics.
- Add provider health so failed scans cannot imply removal.
- Keep Windows and WSL as separate scopes.
- Publish atomically from ignored local staging.
- Migrate canonical structured files from YAML to JSON before real data exists, keeping V1 PowerShell maintenance dependency-free.

## Documentation changed

Added/updated research, discovery, implementation, architecture, development, schema, privacy, roadmap, collection, README, CURRENT, and durable-decision documents. Canonical skeleton is now JSON and includes `context/status.json`.

## Next

Implement Phase A shared PowerShell runtime/helpers, then structured Windows providers, discovery providers, reconciliation, rendering/validation/sync, followed by the first real-machine Full Audit.
