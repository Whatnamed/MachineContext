# Devlog — 2026-10-08 Agy CLI update

Scope: upgrade Agy CLI from 1.2.16 to official stable latest 1.3.1 via native `agy update`, verify executable resolution, backup preservation, and user-global rules loading, and publish the canonical sync.

## Upgrade details

| Tool | Before → After | Official stable latest at execution time | Mechanism actually used |
| --- | --- | --- | --- |
| Agy | 1.2.16 → **1.3.1** | GitHub `google-antigravity/antigravity-cli` latest `1.3.1` (2026-10-07) | `agy update` (native updater; verification + install steps all green) |

## Verification

- Command resolution and binary layout:
  - `where.exe agy` resolves to `%LOCALAPPDATA%\agy\bin\agy.exe` (junction to `E:\AGY\cli\agy.exe`).
  - `agy --version` outputs `1.3.1`.
  - The updater parked the previous 1.2.16 binary as `agy.exe.1791459303399761800.old` in `E:\AGY\cli`.
- User-global rules live-load verified on 1.3.1:
  - From an isolated scratch git repo with no local `AGENTS.md` / `GEMINI.md`, `agy -p` was probed for the machine-context index path.
  - Model returned `E:\MachineContext\CURRENT.md` (which exists only in `%USERPROFILE%\.gemini\config\GEMINI.md`) and exited 0.

## Canonical changes

- Collector-owned sync:
  - `agy` version 1.2.16 → 1.3.1 in `context/software/ai.json` and `CURRENT.md`.
  - Codex Desktop auto-update drift to `26.930.7945.0` with matching `cua_node` / `cua_repl` path updates in `context/configs/mcp.json`.
  - Flutter transient pipe verification restored (`verified-present`).
  - Storage free space drift and verification heartbeat in `context/status.json`.
