# Devlog — 2026-09-19 Agy 1.2.3 → 1.2.7, and the two supplementary entities that had gone stale

Scope: apply the available Agy CLI update, then run the routine sync. The §8 full-comparison step (mandated after the 2026-08-29 trae lesson) turned up two more silently-stale supplementary desktop entities, and the same sync falsified a qoder curated note. All three were closed in this round.

> **Self-review correction (same session).** The qoder evidence row below first read "13 running Qoder CN processes resolve their executable from `.qoder-versions\0.3.4\`". That was wrong: the actual split is **12 on 0.3.4 plus one leftover still on 0.2.5**. The published curated note was corrected in place by a follow-up commit. The error did not change the recorded version (0.3.4 is corroborated independently by `build-manifest.json`, `.qoder-app-status.json` and the registry), but the process count as written overstated the evidence.

## Upgrade

| Item | Value |
| --- | --- |
| Before | 1.2.3 (`%LOCALAPPDATA%\agy\bin\agy.exe`, 195,186,840 bytes, sha256 `E264FB1C…F0916`) |
| After | **1.2.7** (203,523,736 bytes, sha256 `16260789…4dd22`) |
| Mechanism | `agy update` — native self-updater, in-place; updater reported `Found new version 1.2.7` and its own `Verification successful` |
| Verification | installed file sha512 `3b2008ed…377bd` matches the official `windows_amd64` release manifest (version 1.2.7, build 6731160148115456) |
| Backup | updater parked the previous binary as `agy.exe.1789831711622230000.old`, then removed it itself — no `.old` remains |

- **Location discipline.** `Get-Command agy -All` resolves to exactly one entry at `%LOCALAPPDATA%\agy\bin\agy.exe` both before and after; no `agy.cmd`/`agy.ps1` shim exists under `E:\Dev\npm-global` or `%APPDATA%\npm`. No duplicate install was created.
- **No configuration migration.** `%USERPROFILE%\.gemini\antigravity-cli\settings.json` (mtime 2026-09-10) and `%USERPROFILE%\.gemini\config\GEMINI.md` (mtime 2026-09-15, sha256 `412C925E…C111E`) were untouched; `%USERPROFILE%\.gemini\config\mcp_config.json` is still the 0-byte placeholder, so the MCP inventory is unchanged.
- `agy models` / `agy changelog` work on 1.2.7. The changelog for 1.2.4–1.2.7 contains features and fixes only — no migration steps.

## Global-rules re-verification (why this was not assumed)

1.2.7 explicitly changed customization token budgeting — *"giving user and workspace rules a dedicated 20,000-token budget … so large rule sets no longer evict skills, workflows, subagents, or MCP tools"*. Global-rules loading in this repo has already produced one silent failure (the OMP `enabledProviders` gate, invisible for a full round) and one invalid verification (the 2026-09-15 OMP test run from a directory that owned its own `AGENTS.md`), so the load was re-tested rather than assumed.

Tested from a scratch git repository containing **no** `AGENTS.md`/`GEMINI.md`, using content questions instead of heading enumeration (the model refuses to list its own instruction headings):

| Probe | Result |
| --- | --- |
| `LANG` / `INDEX` / `DESTRUCTIVE` | `LANG=简体中文 INDEX=E:\MachineContext\CURRENT.md DESTRUCTIVE=YES` |
| Negative control (never-provided codeword) | `NONE` |

The three answers match `%USERPROFILE%\.gemini\config\GEMINI.md` lines 5 / 22 / 34 exactly, and the negative control rules out confabulation. The user-global ruleset still reaches the model on 1.2.7.

## Supplementary entities found stale (§8 full comparison)

The 2026-08-29 lesson requires comparing **every** supplementary desktop entity's registry `DisplayVersion` against canonical `observed.version`, not just checking paths. Doing that found two mismatches; both were confirmed against independent evidence before being written.

### qoder 0.2.5 → 0.3.4

No routine provider covers this entity, so it had been stale since the 2026-09-16 correction. Evidence, all agreeing:

- of the 13 running `Qoder CN` processes, 12 resolve their executable from `D:\Qoder-CN\Qoder CN\.qoder-versions\0.3.4\Qoder CN.exe` (the newest cohort, started 22:52+08:00), while 1 leftover (pid 18628, started 12:44+08:00) still runs the older 0.2.5 payload — a stale process, not evidence against the refresh;
- `.qoder-versions\0.3.4\resources\build-manifest.json` → `productVersion 0.3.4` (commit `081b9000`, buildTime 2026-09-19T09:22:27Z, electron 43.1.1);
- `.qoder-app-status.json` → `version 0.3.4`;
- `0.3.4.qoder-update-ready.json` (releaseId 0.3.4, payloadLayout `pending-asar-v1`) staged 2026-09-19T22:35;
- registry `DisplayVersion` now also reads 0.3.4.

The install-root `Qoder CN.exe` is still the 0.1.3 installer baseline, as expected for this versioned-payload layout.

### zcode 3.8.1.5310 → 3.14.0.7681

Also uncovered by the same §8 full comparison (this entity has no routine provider either, so the routine scan alone would not have touched it). Evidence: `D:\ZCode\ZCode\ZCode.exe` FileVersion/ProductVersion `3.14.0.7681` (mtime 2026-09-19T10:13+08:00), the HKCU uninstall entry `ZCode 3.14.0`, and the bundled `@zcode/desktop` package.json version `3.14.0`. The executable path is unchanged.

## Corrections to existing records

1. **The qoder `mcp-router.json` note was wrong.** The 2026-09-16 note claimed the file was absent "and no longer appears anywhere under `.qoder-cn`". This round's sync flipped its `exists` back to `true`, so the claim was investigated instead of re-published. The file is a **runtime-transient** artifact: created at 22:52:43, two seconds after the main Qoder process (pid 26592) started at 22:52:41, and its content carries that same live pid. Its presence tracks whether the app is running, so both readings are legitimate and **neither implies removal**. The note was rewritten in place (not appended beside), so canonical never asserts two contradictory states of the same fact.
2. **OPERATIONS §8's registry claim was too strong.** It stated that Qoder's registry `DisplayVersion` "始终停留在安装器基线" (always the installer baseline). That held on 2026-09-16 (0.1.3) but not on 2026-09-19 (0.3.4) — the registry does follow the payload, just not reliably promptly. §8 now says: the install-root exe is always the baseline and never a version source, while the registry is "possibly current but not independently trustworthy", with the running-process path and `build-manifest.json` still ranked first. §8's entity list also gained `zcode`, and the `mcp-router.json` example now states the runtime-transient semantics.

## Incidental real drift captured by the same sync (not caused by this round)

- **Codex Desktop auto-update** 26.908.9136.0 → 26.915.4065.0 (versioned WindowsApps path), with the matching `cua_repl` / `node_repl` MCP command paths following in `mcp.json`; the old `cua_node\b58ca2eaa616c2da` runtime directory is gone and the new `df473e5367fa2b42` one exists.
- **`%USERPROFILE%\.dotnet\tools` added to the user PATH** (`entry_count` 36 → 37), created by the .NET SDK's first-run sentinels on 2026-09-19 23:28; the directory itself does not exist yet, and the SDK state is still `absent` (no `sdk` directory, `dotnet --list-sdks` empty) — so the `dotnet` entity is unchanged.
- Storage free-space heartbeat on C:/D:/E:.

## Canonical

- Routine provider refresh: `agy` 1.2.3 → 1.2.7, `codex-desktop` 26.908.9136.0 → 26.915.4065.0.
- Curated (`.local/curated-2026-09-19-agy-upgrade.ps1`): the agy upgrade record with hashes and manifest verification; the agy global-rules re-verification; `qoder` 0.2.5 → 0.3.4 with the payload evidence and the `mcp-router.json` retraction; `zcode` 3.8.1.5310 → 3.14.0.7681.
- Docs: `OPERATIONS.md` §8 registry-authority correction, `zcode` added to the stale-entity list, and the runtime-transient `mcp-router.json` note.
- No collector, schema, or test change this round — both stale entities are one-time curated refreshes by design (§8), not new collection capability, so the test gate was not *required*. The suite was run anyway and passed in full.

## Gates

- `sync.ps1`: all ten providers success, validation ok.
- `git diff` reviewed line by line; every canonical change is accounted for above.
- `validate.ps1`: 0 errors, 0 findings.
- `tests/run-tests.ps1`: all tests passed (run although not required — no collector or test code changed).
- Third sync idempotent: `ai.json`, `mcp.json`, `qoder.json` and `machine.json` byte-identical; only the `verified_at` heartbeat moved in `context/status.json` and `CURRENT.md`.
- Privacy sweep over `git diff context/` clean.
