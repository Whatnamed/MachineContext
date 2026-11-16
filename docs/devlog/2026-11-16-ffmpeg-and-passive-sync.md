# Devlog — 2026-11-16 FFmpeg CLI onboarding and read-only sync

Scope: Record the user's `Gyan.FFmpeg` installation (and confirm prior removal of Python `imageio-ffmpeg`), add routine CLI collection/normalization support for `ffmpeg`, and run a read-only `Quick` sync to publish passive machine drift accumulated since `2026-11-01`. No applications or machine settings were installed, upgraded, or modified during this session.

## What changed

### 1. Routine `ffmpeg` collection (`OPERATIONS.md` §7)

- `scripts/collectors/runtimes.ps1`: added `ffmpeg` (`kind: cli`, `args: @('-version')`) to `Get-McRuntimeDefinitions`.
- `scripts/lib/normalize.ps1`: added an FFmpeg banner rule to `ConvertTo-McSemanticVersion` so `ffmpeg version 9.0.2-full_build-www.gyan.dev ...` normalizes to `9.0.2` (stripping Gyan.dev `-full_build`/`-essentials_build` suffixes instead of truncating at `_`).
- `scripts/lib/reconcile.ps1`: added `'ffmpeg'` to the `'runtimes-package-managers-toolchain'` map in `Get-McProviderFailureEvents`.
- `tests/run-tests.ps1`: added an FFmpeg banner assertion in `semantic version and banner normalization` and a parity assertion covering `Get-McRuntimeDefinitions` vs `Get-McProviderFailureEvents` in `provider failure must not imply removal`.
- `docs/COLLECTION_SPEC.md`: listed FFmpeg under §I.

### 2. Canonical FFmpeg record & curation (`OPERATIONS.md` §6)

- `context/software/development.json`: recorded `ffmpeg` `9.0.2` via persistent User PATH link `%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe` (`verification: verified-present`, `provider: command`).
- Added `curated.notes` via `.local/curate-ffmpeg-2026-11-16.ps1` documenting the `winget` package (`Gyan.FFmpeg`), sibling `ffplay.exe`/`ffprobe.exe` links, update channel (`winget upgrade Gyan.FFmpeg`), KeyShot Studio's separate off-PATH internal binary (`D:\Program Files\KeyShot Studio\bin\ffmpeg.exe`), and the user's prior uninstall of `imageio-ffmpeg` from `D:\Python\3.12.10` (global pip packages are not tracked as separate entities per `COLLECTION_SPEC.md` §G).

### 3. Passive drift published (not caused by this session)

- **OS / shells (`context/machine.json`)**: Windows 11 Core `25H2` (`26200.9168`) → `26H2` (`26300.9711`); `cmd.exe` `10.0.26200.9168 → 10.0.26300.9711`; `powershell.exe` `5.1.26100.9168 → 5.1.26100.9711`.
- **GPU driver (`context/machine.json`)**: NVIDIA GeForce RTX 3070 Laptop GPU `616.92 → 621.14`.
- **Storage free space (`context/machine.json`)**: `C:` `20.8 → 34.8 GiB`, `D:` `29.0 → 15.8 GiB`, `E:` `66.2 → 144.0 GiB`.
- **Persistent PATH (`context/machine.json`)**: added `%LOCALAPPDATA%\Microsoft\WinGet\Links` (`entry_count` `67 → 68`).
- **.NET runtimes (`context/software/development.json`)**: `.NET` 8.0 shared runtimes `8.0.21 → 8.0.33` (still no system SDK).
- **Codex Desktop & MCP (`context/software/ai.json`, `context/configs/mcp.json`)**: `codex-desktop` `26.1027.3384.0 → 26.1111.2228.0`; `codex-cli` MCP `cua_repl`/`node_repl` paths updated to `OpenAI.Codex_26.1106.6628.0_x64__2p2nqsd0c76g0`.
- **AI config projections (`context/configs/ai/codex-cli.json`, `qoder.json`)**: `codex-cli` now reflects `gpt-6.1-sol`, `model_context_window: 500000`, `model_reasoning_effort: high` (and `model_auto_compact_token_limit` absent); `qoder` gained five enabled marketplace plugins (`office-docx`, `office-excel`, `paper-format-check`, `Presentations`, `research-copilot`).

## Verification

- `pwsh tests/run-tests.ps1`: all test blocks passed (`All MachineContext tests passed.`).
- `pwsh scripts/sync.ps1 -RepoRoot E:\MachineContext -AllowDirty`: `overall_health: success`, all 10 providers `success`, `validation.ok: true` (`warning_count: 0`).
- `pwsh scripts/validate.ps1 -RepoRoot E:\MachineContext` after applying `curated.notes`: `ok: true`, 0 findings.
- Repeat dry-run `pwsh scripts/sync.ps1 -RepoRoot E:\MachineContext -AllowDirty -NoPublish` (`run_id: 20261116-032258645-6799f94b`): all 10 providers `success`, `validation.ok: true`, and `git diff --no-index` against `CURRENT.md` and all `context/` JSON files produced zero diffs (`curated.notes` preserved).
- Privacy sweep across `git diff context/ CURRENT.md`: clean.
