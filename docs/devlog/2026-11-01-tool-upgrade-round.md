# Devlog — 2026-11-01 Developer and AI Tooling Stable Upgrade Round

Scope: In-place stable upgrade across the specified developer toolchain and AI CLI tooling,
respecting existing install roots, package prefixes, and PATH management models;
minimal smoke verification per tool; disk cleanup of obsolete installer and update
residues; and canonical synchronization via standard Operations runbook.

## Upgrades (Before → After, Official Release Evidence, Mechanism)

| Tool | Before → After | Official Stable Evidence | Mechanism Actually Used |
| --- | --- | --- | --- |
| **Claude Code** | 2.1.296 → **2.1.316** | npm tag `latest = 2.1.316` | `npm install --prefix D:\Claude\cli @anthropic-ai/claude-code@2.1.316` in dedicated prefix; `claude.cmd` unchanged |
| **Codex CLI** | 0.162.1 → **0.166.0** | npm dist-tag `latest = 0.166.0` | `npm install --prefix E:\Codex\codex-cli @openai/codex@0.166.0` in dedicated prefix; `codex.cmd` unchanged |
| **Agy CLI** | 1.3.6 → **1.4.12** | GitHub `google-antigravity/antigravity-cli` `1.4.12` | Official binary extracted to `%LOCALAPPDATA%\agy\bin\agy.exe` (junction to `E:\AGY\cli\agy.exe`) |
| **Grok Build CLI** | 1.0.52 → **1.0.70** | `grok update --check --stable` → `1.0.70` | `grok update --stable` native updater at `D:\GrokBuild\home\bin\grok.exe` |
| **Oh My Pi / OMP** | 18.10.3 → **18.14.2** | `omp update` / GitHub `can1357/oh-my-pi` `v18.14.2` | `omp update` native updater in-place at `D:\OMP\omp.exe` |
| **Git for Windows** | 2.56.0.windows.2 → **2.56.0.windows.4** | GitHub `git-for-windows/git` `v2.56.0.windows.4` | Official vendor installer `Git-2.56.0.4-64-bit.exe` `/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /DIR=D:\Git\Git` |
| **Git LFS (bundled)** | 3.8.0 → **3.8.1** | Bundled component inside Git for Windows 2.56.0.4 | Automatically refreshed by Git for Windows installer at `D:\Git\Git\cmd\git-lfs.exe` |
| **Go** | 1.26.7 → **1.27.3** | Official `go.dev/dl/?mode=json` latest stable `go1.27.3` | Extracted official distribution into existing root `D:\Go` (`go.exe` at `D:\Go\bin\go.exe`, `GOROOT = D:\Go`) |
| **uv / uvx** | 0.13.0 → **0.13.6** | GitHub `astral-sh/uv` `0.13.6` | `uv self update` in place at `E:\Dev\uv` |
| **Node.js 22 LTS** | 22.23.2 → **22.23.4** | Official `nodejs.org/dist/index.json` latest v22 LTS patch `v22.23.4` (Jod) | Extracted official `node-v22.23.4-win-x64.zip` into existing root `D:\Node.js\Node.js` (npm upgraded 10.9.8 → 10.9.9) |
| **Rust compiler (rustc)** | 1.99.0 → **1.99.1** | `rustup check`: `1.99.0 -> 1.99.1 (58cf8f9c3)` | `rustup update stable` on existing `stable-x86_64-pc-windows-msvc` toolchain |
| **Cargo** | 1.99.0 → **1.99.1** | Bundled with Rust stable 1.99.1 | Refreshed via `rustup update stable` |
| **rustup** | 1.29.1 → **1.29.2** | `rustup check`: `1.29.1 -> 1.29.2` | `rustup self update` in `%USERPROFILE%\.cargo\bin` |
| **Bun** | 1.4.2 → **1.4.4** | GitHub `oven-sh/bun` `bun-v1.4.4` | Official `bun.sh/install.ps1` with `BUN_INSTALL=%USERPROFILE%\.bun`, `-NoPathUpdate -NoRegisterInstallation -NoCompletions` |
| **Supabase CLI** | 2.120.0 → **2.122.0** | npm / GitHub `supabase` `2.122.0` (2.x Stable) | New versioned prefix `D:\Tools\SupabaseCLI\2.122.0` (`npm install supabase@2.122.0 --save-dev`) + User PATH index 16 repointed preserving `ExpandString` |
| **VS Code Desktop** | 1.134.0 → **1.144.0** | Official VS Code update API `win32-x64-user/stable/latest` = `1.144.0` | Official `VSCodeUserSetup-x64-1.144.0.exe` `/VERYSILENT /NORESTART /MERGETASKS=!runcode /DIR="D:\VSCode\Microsoft VS Code"` |
| **GitHub CLI (gh)** | 2.102.0 → **unchanged (2.102.0)** | GitHub `cli/cli` `v2.103.3` | **Skipped (recorded blocker)**: Installed at `%PROGRAMFILES%\GitHub CLI\gh.exe` via machine-scope MSI (`ALLUSERS=1`), requiring administrator elevation (`msiexec` returns 1603 in unelevated agent context). Preserved existing install without creating duplicate user-scope copies. |

## Disk Cleanup of Obsolete Installer and Update Residues

Over **1.64 GB** of confirmed obsolete update residues and installer artifacts were safely removed from target tool directories:
- `D:\GrokBuild\home\bin\grok.exe.old` (161.51 MB)
- `D:\OMP\omp.exe.*.bak` (232.94 MB)
- `D:\Tools\SupabaseCLI\2.109.1` (218.41 MB)
- `D:\Tools\SupabaseCLI\2.116.0` (141.27 MB)
- `D:\Tools\SupabaseCLI\2.118.0` (150.43 MB)
- `D:\Tools\SupabaseCLI\2.119.0` (151.15 MB)
- `D:\Tools\SupabaseCLI\2.120.0` (151.02 MB)
- `D:\Node.js\node-v22.14.0-x64.msi` (29.48 MB)
- `D:\Node.js\node-v22.23.2-win-x64.zip` (34.03 MB)
- `D:\Go\go1.24.11.windows-amd64.msi` (68.69 MB)
- `D:\VSCode\VSCodeUserSetup-x64-1.117.0.exe` (150.88 MB)
- `D:\Git\Git-2.54.0-64-bit.exe` (62.16 MB)
- `E:\Dev\uv\*__selfdelete__*.exe` (88.21 MB)

Retained notable large residue:
- `D:\Node.js\Node.js-old` (~91.9 MB): legacy directory from April 2025 MSI install; protected by Administrator ACLs and left untouched for manual elevated removal if desired.

## Verification Summary

All upgraded tools passed functional resolution and minimal smoke checks:
- Claude Code 2.1.316: `claude -p "Reply with exactly: OK"` → `OK` (exit 0)
- Codex CLI 0.166.0: `codex exec --skip-git-repo-check "Reply exactly: OK"` → `OK` (exit 0, 13,311 tokens)
- Agy CLI 1.4.12: `agy -p "Reply with exactly: OK"` → `OK` (exit 0)
- Grok Build CLI 1.0.70: `grok --version` → `1.0.70 (f50904eaee6c)`, binary operational
- OMP 18.14.2: `omp -p "Reply exactly: OK"` → `OK` (exit 0)
- Git 2.56.0.4 & Git LFS 3.8.1: command resolution and versions verified
- Go 1.27.3: `go version` and `go env GOROOT` (`D:\Go`) verified
- uv / uvx 0.13.6: versions verified
- Node.js 22.23.4 / npm 10.9.9: `node -e "console.log(process.version)"` verified
- Rustc 1.99.1, Cargo 1.99.1, rustup 1.29.2: toolchain verified
- Bun 1.4.4: `bun -e "console.log(1+1)"` → `2` verified
- Supabase CLI 2.122.0: version and PATH resolution verified
- VS Code 1.144.0: `code --version` verified
