# Devlog — 2026-09-05 AI CLI upgrade round

Scope: the four AI CLIs named in the 2026-09-05 plan (Agy, Codex CLI, OpenCodex, OMP). Grok Build (no update), DSH (RC skipped), Claude Code, auto-update desktop apps, other runtimes, and design software were explicitly out of scope.

## Version results (all primaries preserved, no new duplicates)

| Tool      | Before | After   | Update mechanism                              | Primary after |
| --------- | -----: | ------: | --------------------------------------------- | ------------- |
| Agy       | 1.1.22 | 1.1.27  | native `agy update` (self-updater, sha-verified) | `%LOCALAPPDATA%\agy\bin\agy.exe` (unchanged) |
| Codex CLI | 0.152.1 | 0.153.4 | `npm install -g @openai/codex@0.153.4 --prefix E:\Codex\codex-cli` | `E:\Codex\codex-cli\codex.cmd` (unchanged) |
| OpenCodex | 2.40.0 | 2.42.0  | `npm install -g @bitkyc08/opencodex@2.42.0 --prefix E:\Dev\npm-global` | `E:\Dev\npm-global\opencodex.cmd` (unchanged) |
| OMP       | 18.1.2 | 18.1.10 | `omp update` (in-place, sha256 verified)       | `D:\OMP\omp.exe` (unchanged) |

Notes:

- The plan's baseline expected Agy 1.1.25, but the native self-updater had already moved the machine to 1.1.25 unattended before execution; this round then updated it to the current official stable **1.1.27** (confirmed against the official `windows_amd64` release manifest). `agy changelog` for 1.1.25–1.1.27 contains only fixes/improvements — no breaking changes or migrations. `agy models` works and Gemini 3.8 Flash is visible.
- Codex 0.153.4 (rust-v0.153.4, GitHub latest, non-prerelease) and OpenCodex 2.42.0 (npm latest) matched the plan's targets at execution time; OMP v18.1.10 (GitHub latest, non-prerelease) likewise. The OMP updater's own sha256 for the new binary was re-verified locally against the installed file.
- OMP config migration check: SHA256 of `%USERPROFILE%\.omp\agent\config.yml` and `models.yml` are byte-identical before/after — the updater replaced only the binary and left no configuration migration. `settings.json` does not exist in this layout (only config.yml/models.yml). The 18.1.3–18.1.10 feature/breaking changes (eval, browser automation, subagents, Plan Review) are behavior-level; local config remains valid. `omp.exe.*.bak` in `D:\OMP` is normal updater behavior and stays out of the inventory.
- OpenCodex: port 10100 was not listening before or after (nothing to restore); `%USERPROFILE%\.opencodex` config untouched. Codex CLI: `%USERPROFILE%\.codex` untouched; the `codex.ps1/.cmd` shims are the npm triple in the same dedicated root, not a second installation.
- Agy updater dir: `update.lock` (dated 2026-08-18) exists but does not block updates (updater ran fine); left untouched per plan.

## Agy config-path audit (Phase 4 of the plan)

- `%USERPROFILE%\.gemini\settings.json` belongs to **Gemini CLI** (keys: ui/statusLine/mcpServers.pencil) — it is already correctly listed in OPERATIONS §4.7 and mcp.json as the Gemini CLI MCP source.
- Agy's actual settings are `%USERPROFILE%\.gemini\antigravity-cli\settings.json` (agentMode/model/toolPermission/trustedWorkspaces…), matching current official docs.
- `%USERPROFILE%\.gemini\config\mcp_config.json` exists but is an empty object; `agy mcp list` reports "No MCP servers configured". **No MCP inventory change**: the canonical agy entity's config_paths was corrected to the antigravity-cli settings file (one-time correction with user-confirmed evidence + curated note). The mcp.json `unresolved` note for agy remains accurate.

## Incidental real drift captured by the same sync (not caused by the upgrades)

- Codex Desktop auto-update 26.831.2377.0 → 26.901.4073.0 (versioned WindowsApps path), with the matching `cua_repl`/`node_repl` MCP command paths following.
- Codex CLI config profile: user changed `model` (gpt-5.6-luna → gpt-6-astra) and `model_reasoning_effort` (max → low) in config.toml on 2026-09-05 morning (pre-existing file mtime, unrelated to the npm update); new top-level key `service_tier` appears as `unprojected_keys` (allowlist deliberately not expanded; value is a billing/perf tier preference and is not projected).
- ZCode provider toggle (BigModel - Coding Plan disabled) — user action in the desktop app.
- Storage free-space heartbeat on C:/D:/E:.

## Follow-up: Agy global MCP source added to the collector (reviewer feedback)

The main round left the mcp.json `unresolved` note "agy: no file-based MCP configuration discovered" in place, but the official Antigravity CLI global MCP file `%USERPROFILE%\.gemini\config\mcp_config.json` does exist on this machine (a 0-byte placeholder) — a future `/mcp add` in Agy would have been invisible to routine sync. `config-profiles.ps1` now collects it as the sixth MCP source:

- reads the official `mcpServers` key through the shared sanitizers (transport/command/normalized command/safe URL/sequence-checked args/env names only; `headers` are never read);
- a 0-byte or whitespace file is a normal observation (source recorded, 0 servers, no redaction, no unresolved) — the machine's real file is exactly this state; only a genuinely malformed source records `unparseable-source`, and only a missing file stays unresolved;
- fixtures: `{}`, 0-byte, one stdio server, and a remote server with Authorization/X-Api-Key headers plus a credentialed URL (userinfo/query stripped, credential argv pair dropped);
- docs: OPERATIONS §4.7 now lists six MCP sources and spells out the Gemini CLI vs Agy file distinction; COLLECTION_SPEC records the empty-file semantics.

## Gates

sync (validation ok) → agy one-time correction → diff review (line by line) → validate 0 findings → second sync idempotent → privacy sweep clean. No collector/schema changes this round, so the test suite gate was not triggered (no code changed).
