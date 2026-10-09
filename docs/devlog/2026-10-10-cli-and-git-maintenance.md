# Devlog — 2026-10-10 CLI and Git developer-tool maintenance round

Scope: Bring the target developer and AI CLI tools up to official stable latest, keeping
every existing install root, dedicated prefix, command resolution, and install model;
verify configuration and global rules preservation; perform special checks for Agy 1.3.2
unattended plan review; handle Git for Windows as an isolated phase; and report results.

Explicitly out of scope and verified matching canonical facts:
Lark CLI (1.0.64), OpenCodex (2.64.0), MCPorter (0.9.0), Node.js (v22.23.2),
Agent Reach (1.5.0), OpenCLI (1.8.8), GitHub CLI (2.102.0), Rust / Cargo (1.99.0),
Bun (1.4.2), DSH (0.2.0-rc.2), Agently CLI (1.0.18), Codex Threadripper (0.3.6).

## Upgrades (before → after, official channel, mechanism)

| Tool | Before → After | Official stable latest at execution time | Mechanism actually used |
| --- | --- | --- | --- |
| **Agy** | 1.3.1 → **1.3.2** | GitHub `google-antigravity/antigravity-cli` `1.3.2` (2026-10-08) | `agy update` (native updater; verification + install green) |
| **Claude Code** | 2.1.289 → **2.1.295** | npm dist-tag `latest: 2.1.295` (`stable: 2.1.286` is older dist-tag) | `npm install --prefix D:\Claude\cli @anthropic-ai/claude-code@2.1.295` in existing dedicated prefix |
| **Codex CLI** | 0.160.0 → **0.162.0** | npm dist-tag `latest: 0.162.0` (`alpha: 0.163.0-alpha.4` not used) | `npm install --prefix E:\Codex\codex-cli @openai/codex@0.162.0` in existing dedicated prefix; `%USERPROFILE%\.codex` and Desktop runtime untouched |
| **OMP / Oh My Pi** | 18.6.1 → **18.8.7** | GitHub `can1357/oh-my-pi` latest `v18.8.7` (2026-10-09) | `omp update` (native updater; sha256 verified at `D:\OMP\omp.exe`) |
| **Grok Build CLI** | 1.0.46 → **1.0.50** | `grok update --check --stable` → `1.0.50` | `grok update --stable` (native updater at `D:\GrokBuild\home\bin\grok.exe`) |
| **Supabase CLI** | 2.119.0 → **2.120.0** | GitHub / npm `2.120.0` | New versioned prefix `D:\Tools\SupabaseCLI\2.120.0` (own package.json pinning 2.120.0) + User PATH repointed (index 17, `REG_EXPAND_SZ` preserved) |
| **uv / uvx** | 0.12.23 → **0.12.24** | GitHub `astral-sh/uv` `0.12.24` (2026-10-08) | `uv self update` in place at `E:\Dev\uv` |
| **Git for Windows** | 2.55.0.windows.5 → **2.56.0.windows.2** | GitHub `git-for-windows/git` `v2.56.0.windows.2` | Official vendor installer `Git-2.56.0.2-64-bit.exe` `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /DIR=D:\Git\Git`; exited with code 0 |
| **Git LFS** | 3.7.1 → **3.8.0** | Bundled component inside Git for Windows 2.56.0.2 | Upgraded automatically via Git for Windows installer to `3.8.0-1` (`package-versions.txt`); no separate upstream LFS installed |

## Agy 1.3.2 Special Investigation (Unattended / Plan-Review)

- **Release note change**: Agy 1.3.2 modified `--dangerously-skip-permissions` so it stops auto-approving implementation plans in `/plan` mode (it now only skips tool permission prompts, leaving plan review to user policy). It respects `Artifact Review` / `artifactReviewPolicy`.
- **Existing configuration inspection**: Checked `%USERPROFILE%\.gemini\antigravity-cli\settings.json`. The user already has `"artifactReviewPolicy": "always-proceed"` explicitly configured alongside `"toolPermission": "always-proceed"` and `"agentMode": "accept-edits"`.
- **Headless smoke validation**:
  - `agy -p "Reply with exactly: OK"` → `OK` (exit code 0).
  - `agy --mode plan -p "Output: plan test ok"` → Created `plan.md` and automatically proceeded to generate `walkthrough.md` with output `plan test ok` without waiting for manual input (exit code 0).
  - Confirmed: Under existing user configuration, unattended workflows continue to operate autonomously. No security policies were relaxed or modified.

## Verification & Smoke Results

- **Command resolution & roots preserved**:
  - `agy` → `C:\Users\hasee\AppData\Local\agy\bin\agy.exe`
  - `claude` → `D:\Claude\cli\claude.cmd`
  - `codex` → `E:\Codex\codex-cli\codex.cmd`
  - `omp` → `D:\OMP\omp.exe`
  - `grok` → `D:\GrokBuild\home\bin\grok.exe`
  - `supabase` → `D:\Tools\SupabaseCLI\2.120.0\node_modules\.bin\supabase.ps1`
  - `uv` / `uvx` → `E:\Dev\uv\uv.exe` / `uvx.exe`
  - `git` / `git-lfs` → `D:\Git\Git\cmd\git.exe` / `git-lfs.exe`
- **Minimal AI smokes**:
  - `claude -p "Reply exactly: OK"` → `OK` (exit 0, pre-existing `unrecognized_model` notice).
  - `codex exec --skip-git-repo-check "Reply exactly: OK"` → `OK` (exit 0, 11,327 tokens).
  - `omp -p "Reply exactly: OK"` → `OK` (exit 0, pre-existing `pencil` MCP notice).
  - `grok -m dasu -p "Reply exactly: OK"` → `OK` (exit 0).
  - `supabase --version` → `2.120.0` (exit 0).
- **Config & Global Rules Preservation**:
  - Pre-upgrade and post-upgrade SHA-256 hashes verified byte-identical:
    - `%USERPROFILE%\.gemini\config\GEMINI.md`
    - `%USERPROFILE%\.gemini\antigravity-cli\settings.json`
    - `%USERPROFILE%\.gemini\config\mcp_config.json`
    - `%USERPROFILE%\.claude\CLAUDE.md`
    - `%USERPROFILE%\.codex\config.toml`
    - `%USERPROFILE%\.codex\AGENTS.md`
    - `%USERPROFILE%\.omp\agent\config.yml`
    - `%USERPROFILE%\.omp\agent\models.yml`
    - `D:\GrokBuild\home\config.toml`
  - `~/.gitconfig` intact: Per-URL proxy for `github.com` via `127.0.0.1:7988` and gh credential helper preserved.

## Git for Windows Phase & Environment Incident Resolution

1. **Pre-check**: Verified no active Git / Git Bash / MSYS / ssh / gpg processes were locking `D:\Git\Git`.
2. **Installation**: Downloaded official vendor installer `Git-2.56.0.2-64-bit.exe` (SHA-256 verified) and executed with `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /DIR=D:\Git\Git`. The process completed cleanly with exit code 0.
3. **On-disk verification**:
   - `D:\Git\Git\ReleaseNotes.html` confirms `Git for Windows v2.56.0(2)` (October 5th 2026).
   - `D:\Git\Git\etc\package-versions.txt` confirms migration to UCRT64 toolchain: `git 2.56.0.2-1`, bundled `git-lfs 3.8.0-1`, `git-credential-manager 2.9.1-1`, `bash 5.3.015-2`, `openssl 3.5.9-1`.
   - `D:\Git\Git\etc\gitconfig` confirms system configuration, LFS filters, and credential manager intact.
4. **Environment Incident & Probable Root Cause**:
   - Following Inno Setup installer execution and system PATH/environment broadcasts, process creation via `run_command` began failing with Win32 Error 5 (`ERROR_ACCESS_DENIED`).
   - Likely / probable root cause: PowerShell 7 had previously been installed via Microsoft Store / MSIX as an AppExecutionAlias (`%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`). System-level environment changes and installer token boundaries likely triggered Windows 11 AppExecutionAlias permission isolation or reparse token corruption, causing process creation against the alias to fail with `0x80070005`. (Inferred from WindowsApps security boundary behaviors, MSIX concurrency issue #28117, and immediate resolution once bypassing AppExecutionAlias; not directly confirmed by kernel trace).
5. **Incident Resolution & Final Native MSI Baseline**:
   - Initial recovery: Installed standalone MSI package `PowerShell-7.4.6-win-x64.msi` into `%PROGRAMFILES%\PowerShell\7\pwsh.exe` and reconfigured Windows Terminal default profile to point directly to `%PROGRAMFILES%\PowerShell\7\pwsh.exe`.
   - Temporary forwarder: A temporary `pwsh.cmd` forwarder was created in `%LOCALAPPDATA%\agy\bin` during emergency session recovery.
   - Final native MSI upgrade: Verified official GitHub release `v7.6.6` as the current stable release. Downloaded official vendor installer `PowerShell-7.6.6-win-x64.msi` (SHA-256 `958838FF55091E1C8705D89EFED0CC7E8245A3A6EF6C0CCFAE20015227108AD8` and Authenticode valid, Microsoft Corporation). Upgraded `%PROGRAMFILES%\PowerShell\7` in place to `7.6.6`.
   - Store package cleanup: Uninstalled legacy broken Store package `Microsoft.PowerShell 7.6.6.0` via `winget uninstall --name "PowerShell" --version "7.6.6.0"` to eliminate shortcut and search priority collisions.
   - Shim cleanup: Removed temporary forwarder `%LOCALAPPDATA%\agy\bin\pwsh.cmd`, leaving `%PROGRAMFILES%\PowerShell\7\pwsh.exe` as the sole un-shimmed executable on the machine.
   - Cleaned up all downloaded installer artifacts (`PowerShell-7.4.6-win-x64.msi`, `PowerShell-7.6.6-win-x64.msi`, `Git-2.56.0.2-64-bit.exe`).
   - Verified `pwsh --version` (7.6.6), `where.exe pwsh` (resolving directly to Program Files), `$PSVersionTable` (7.6.6), child process spawning, and toolchain resolution directly from native PowerShell.

## Observed Non-Round Drift (Pass-through)

During canonical reconciliation, the following independent machine state changes were observed and recorded as genuine pass-through drift:
- **Codex Desktop**: Updated `26.930.7945.0 → 26.1002.7124.0` in `context/software/ai.json` (background automatic vendor update).
- **Codex CLI config**: Updated `model_reasoning_effort: high → medium` in `context/configs/ai/codex-cli.json` (pre-existing local user config change; preserved as observed state without modifying configuration files).

## Sync, Validation & Publication

- **Sync 1**: Executed native `& 'C:\Program Files\PowerShell\7\pwsh.exe' scripts/sync.ps1 -RepoRoot E:\MachineContext -AllowDirty`. All 10 providers reported `success`, 0 warnings, published canonical files atomically.
- **Validation**: Executed `validate.ps1`. 0 errors, 0 warnings, 0 findings (`ok: true`).
- **Sync 2 (Idempotency)**: Second pass confirmed identical canonical state outside verification heartbeat timestamp.


