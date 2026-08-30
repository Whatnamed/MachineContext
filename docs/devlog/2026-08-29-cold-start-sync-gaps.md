# 2026-08-29 — cold-start sync gaps closed (WorkBuddy, Trae refresh, Qoder profile)

## Context

Stress-testing the new runbook with the user's actual changes ("changed OMP/Qoder configs,
installed a new agent") found three leaks a cold agent would have missed:

1. **WorkBuddy 5.3.14** (`E:\WorkBuddy`, config home `%USERPROFILE%\.workbuddy`) was installed but
   a plain sync does not promote registry candidates into canonical entities.
2. **Trae** had auto-upgraded 0.1.39 → 0.1.58; its filesystem-evidence entity is supplemental and
   never refreshed (same staleness class as the claude-desktop MSIX case).
3. **Qoder config was not collected at all**: `%USERPROFILE%\.qoder-cn\settings.json` holds enabled
   plugins and MCP server declarations, and none of it reached canonical.

## Changes

The user then revealed the stress test was real: two Doubao desktop apps were installed and
WorkBuddy had been updated, so the same round processed them live through the playbook:

- **Doubao 2.25.16 / Doubao Work 2.25.18** (`D:\Doubao`, `D:\DoubaoWork`, HKCU uninstall entries)
  added as entities with registry + user-confirmed evidence; the incidental 豆包输入法 (IME) was
  deliberately excluded from AI tooling. Path observations track install and data directories.
- Data/code changes:

- `scripts/collectors/config-profiles.ps1`
  - New `Get-McQoderConfigProfile` projecting `%USERPROFILE%\.qoder-cn\settings.json` with a
    minimal allowlist (`enabledPlugins`, dynamic keys → strict scalar leaves); unknown top-level
    keys (`mcpServers` included) are recorded by name only.
  - `mcp-router.json` is recorded as `sensitive-config` existence only — it contains a live
    runtime API key (verified during design; never parsed).
  - `Get-McMcpInventoryRecord` gains a fifth source: Qoder `settings.json#mcpServers` projected
    with the standard rules (name/transport/url safe/command/args sequence check); the
    Qoder-specific `qoder_url` field is never read.
- `scripts/collectors/ai-tools.ps1` — path observations for `.workbuddy` (config directory) and
  `E:\WorkBuddy` (install directory).
- Canonical (one-time publish correction): WorkBuddy entity added (registry
  `HKCU/.../BFD312E9-…` + user-confirmed usage, purpose + config-home note); Trae version
  refreshed to 0.1.58.
- `docs/OPERATIONS.md`: the gate list now requires reconciling user-reported changes against the
  diff and explicitly covers "new installs do not auto-promote" and "new tools' configs are not
  collected"; §4.6 Qoder playbook rewritten for the profile + fifth MCP source; §6 covers
  one-time entity addition/refresh; §7 step 0 explains how to locate a new tool's config
  locations; §8 generalized the supplemental-entity staleness limitation (trae/qoder/workbuddy +
  MSIX).
- Fixtures/tests: qoder profile (plugins projected, unprojected keys, sensitive router record,
  validation clean) and MCP inventory (six servers across five sources, qoder_url never leaks).
