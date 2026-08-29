# Changelog

MachineContext uses Git for detailed history. This file records only notable project-level changes.

## Unreleased

### Added

- Private files-first MachineContext repository and canonical context structure.
- Product, development, collection, architecture, roadmap, decision, privacy, and schema documentation.
- Historical bootstrap hints for the first local audit, explicitly separated from canonical truth.
- Reference research covering IO Inventory, DevEnvInfoServer, Windows inventory sources, Everything, envinfo, and osquery.
- Layered `Quick / Discover / Enrich / Full` discovery and evidence-reconciliation design.
- V1 implementation guide covering provider health, stable identity, observed/curated ownership, atomic publication, Windows-specific edge cases, privacy, and Git synchronization.
- `context/status.json` for compact published verification/provider-health state.
- Script, collector, library, test-fixture, and schema scaffolding for V1.
- Development log convention.
- `context/configs/` AI configuration profile module with source-specific allowlisted projections (OMP, DSH, ZCode, OpenCodex, Codex CLI shared config), a cross-tool MCP inventory, credential redaction to environment-variable names, validator privacy gates, and fixture tests.
- Qoder CN in the AI tooling inventory (CLI verified from its known install location when not on PATH) and a Codex CLI configuration profile for the top-level scalar settings shared with the Codex desktop app.

### Changed

- Config projections hardened: per-field allowlists with `unprojected_keys`, sequence-aware MCP argument filtering (split credential flags dropped with their values), `source_state: stale` marking on confirmed source absence, and removal of the ZCode stale-copy fallback.
- Allowlist leaves tightened with a strict `scalar-leaf` spec (unexpected nested mappings rejected, not generically walked), nested-object schemas made mapping-only (scalar values and mixed-shape sequence items rejected), and OMP `install.root` derived from the resolved executable instead of being hardcoded in the collector.
- Canonical structured context migrated from bootstrap YAML to JSON before real machine data was committed, avoiding a PowerShell YAML parser/runtime dependency.
- V1 changed from a checklist-style collector plan to a layered structured-discovery + candidate + verification + reconciliation pipeline.
- Installed-app strategy standardized on Registry/winget enrichment rather than `Win32_Product`/`wmic product`.
- Everything/`es.exe` defined as an optional discovery accelerator, never a required/auto-installed dependency.
- Windows host and WSL are explicitly separate environment scopes.

### Current phase

- V1 collector implementation + Initial Full Audit.
