# 2026-08-29 — Qoder CN joins the inventory; Codex CLI/desktop shared config gets a profile

## Context

The user installed Qoder CN and changed context settings through the Codex desktop
app. Investigation showed:

- Qoder CN 0.1.2 IDE at `D:\Qoder-CN\Qoder CN` (HKCU uninstall entry), with the
  Qoder CLI (`qoderclicn.exe` 1.1.13) and its `qodersec` companion (0.8.9) under
  `%USERPROFILE%\.qodersec\bin`; none of them resolve on PATH.
- The Codex desktop app and the Codex CLI share `%USERPROFILE%\.codex\config.toml`
  (`CODEX_HOME` points at the same directory; the user confirmed the desktop
  settings UI edits this shared file). The repo had no codex-cli config profile —
  the file was only mined for `mcp_servers`.

## Changes

- `scripts/collectors/ai-tools.ps1`
  - New `qoder` definition (command `qoderclicn`) with a `fallback_executable`
    known location; when PATH resolution fails, the collector probes the known
    location and records `command_resolution.command_type: 'known-location'`.
  - Path observations for `.qoder-cn` and `.qodersec` (config directories) and
    the Qoder IDE install directory.
- `scripts/lib/config-projection.ps1` — `Get-McTomlTopLevelScalars`: bounded
  reader for top-level TOML scalar keys; parsing stops at the first table header,
  arrays and inline tables are not parsed.
- `scripts/collectors/config-profiles.ps1` — new `Get-McCodexConfigProfile`
  projecting only the top-level scalar settings (model, sandbox_mode,
  model_reasoning_effort, model_context_window, model_auto_compact_token_limit);
  `[mcp_servers.*]` tables stay with the MCP inventory and `auth.json` is recorded
  as existence only. Wired into `Get-McConfigProfileObservations` (present check +
  `source-missing` state when the file disappears).
- Tests: TOML top-level reader unit test; Codex profile fixture + assertions
  (context values projected, unknown top-level keys recorded in
  `unprojected_keys`, table content and its credentials never reach the profile).
- Docs: COLLECTION_SPEC documents the codex-cli profile, the shared desktop/CLI
  file, and the `fallback_executable` known-location resolution; SCHEMA lists the
  new profile.
