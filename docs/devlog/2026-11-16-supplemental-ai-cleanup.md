# Devlog — 2026-11-16 Supplemental AI desktop refresh and uninstalled entity cleanup

Scope: Refresh stale supplemental AI desktop entities (`OPERATIONS.md` §8) and remove user-confirmed uninstalled entries (`cherry-studio`, `trae`) from `context/software/ai.json`, then run a read-only `Quick` sync and validation gates. No software was installed, upgraded, or modified on the machine.

## What changed

### 1. Removed uninstalled supplemental AI entities (`OPERATIONS.md` §6)

- **`cherry-studio`** (`1.8.1`, `%PROGRAMFILES%\Cherry Studio\Cherry Studio.exe`) and **`trae`** (`0.1.58`, `D:\TRAE_Work_CN\TRAE SOLO CN\TRAE SOLO CN.exe`): verified absent on disk and in Windows Uninstall registry, confirmed deleted by the user, and removed from `context/software/ai.json` (`meta.supplemental_inventory.entity_ids` and `software[]`).

### 2. Refreshed drifted supplemental AI desktop versions (`OPERATIONS.md` §8)

Applied via `.local/refresh-supplemental-ai-2026-11-16.ps1` using repository JSON helpers:

- **`antigravity-desktop`**: `2.17.0 → 2.32.1` (`%LOCALAPPDATA%\Programs\antigravity\Antigravity.exe` FileVersion `2.32.1` / ProductVersion `2.32.1.0`, live running `Antigravity.exe` processes, HKCU Uninstall `"Antigravity 2.32.1"`).
- **`dsh-desktop`**: `0.2.1-rc.2 → 0.2.1-rc.5` (`D:\DSH-desktop\DeepSeek Harness.exe` FileVersion `0.2.1-rc.5` / ProductVersion `0.2.1.0`, HKCU Uninstall `"DeepSeek Harness 0.2.1-rc.5"`, matching bundled `dsh` CLI).
- **`qoder`**: `0.4.2 → 0.5.7` (`D:\Qoder-CN\Qoder CN\.qoder-versions\0.5.7\Qoder CN.exe` present, `.qoder-versions\0.5.7\resources\build-manifest.json` `productVersion: "0.5.7"`, `0.5.7.qoder-update-ready.json` present, HKCU Uninstall `"Qoder CN 0.5.7"`; main `Qoder CN.exe` was not running during the check and install-root `Qoder CN.exe` stays at `0.1.3`).
- **`workbuddy`**: `5.5.6 → 5.9.3` (`E:\WorkBuddy\WorkBuddy.exe` FileVersion `5.9.3` / ProductVersion `5.9.3.0`, HKCU Uninstall `"WorkBuddy 5.9.3"`).
- **`zcode`**: `3.14.3.7762 → 3.16.3.8992` (`D:\ZCode\ZCode\ZCode.exe` FileVersion/ProductVersion `3.16.3.8992`, HKCU Uninstall `"ZCode 3.16.3"`).

### 3. Additional read-only observations (left untouched pending confirmation)

- `context/projects/index.json`: all 8 project paths verified present.
- `context/software/creative.json` & `productivity.json`:
  - `cinema-4d` (`2023.0.0`): `D:\Program Files\Maxon Cinema 4D 2023` and Uninstall entry `"Maxon Cinema 4D 2023"` still exist, though the recorded `Cinema 4D.exe` path returned false (possibly moved/renamed executable).
  - `feishu` (`7.69.9`, `E:\Feishu\Feishu.exe`) and `notion` (`7.7.0`, `%LOCALAPPDATA%\Programs\Notion\Notion.exe`): recorded directories and Uninstall entries are absent; left untouched pending user confirmation.

## Verification

- `pwsh scripts/sync.ps1 -RepoRoot E:\MachineContext -AllowDirty` (`run_id: 20261116-032943837-cfde7004`): `overall_health: success`, all 10 providers `success`, `validation.ok: true` (`warning_count: 0`).
- `pwsh scripts/validate.ps1 -RepoRoot E:\MachineContext`: `ok: true`, 0 findings.
- Repeat dry-run `pwsh scripts/sync.ps1 -RepoRoot E:\MachineContext -AllowDirty -NoPublish` and `git diff --no-index` against `CURRENT.md` and `context/`: 0 diffs.
- Privacy sweep and `git diff --check`: clean.
