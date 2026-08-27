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
- `context/configs/` AI configuration profile module with source-specific allowlisted projections (OMP, DSH, ZCode, OpenCodex), a cross-tool MCP inventory, credential redaction to environment-variable names, validator privacy gates, and fixture tests.

### Changed

- Canonical structured context migrated from bootstrap YAML to JSON before real machine data was committed, avoiding a PowerShell YAML parser/runtime dependency.
- V1 changed from a checklist-style collector plan to a layered structured-discovery + candidate + verification + reconciliation pipeline.
- Installed-app strategy standardized on Registry/winget enrichment rather than `Win32_Product`/`wmic product`.
- Everything/`es.exe` defined as an optional discovery accelerator, never a required/auto-installed dependency.
- Windows host and WSL are explicitly separate environment scopes.

### Current phase

- V1 collector implementation + Initial Full Audit.
