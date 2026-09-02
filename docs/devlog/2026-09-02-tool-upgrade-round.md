# 2026-09-02 — productivity/dev tool upgrade round and OMP pin removal

## Context

The user ordered a full "upgrade → verify on the machine → MachineContext sync → gates →
push" round and explicitly overrode one durable curated semantic: OMP's earlier
"pinned to 18.0.6, do not run `omp update`" policy is obsolete — the tool is in active use
and stable updates are welcome again.

## Tool upgrades (all install locations preserved)

| Tool | Before → After | Mechanism |
|---|---|---|
| Codex CLI | 0.149.1 → 0.152.1 | `npm install -g @openai/codex@latest --prefix E:\Codex\codex-cli` |
| Grok Build | 1.0.4 → 1.0.13 | official `install.ps1` with `GROK_BIN_DIR=D:\GrokBuild\home\bin` |
| OMP | 18.0.6 → 18.1.2 | `omp update` (in-place, sha256-verified, left its own `.bak`) |
| OpenCodex | 2.33.0 → 2.40.0 | `npm -g @bitkyc08/opencodex@latest` |
| pip | 25.0.1 → 26.2.1 | `D:\Python\3.12.10\python.exe -m pip install --upgrade pip` |
| uv / uvx | 0.12.5 → 0.12.9 | `uv self update` (in-place at `E:\Dev\uv`) |
| Git for Windows | 2.54.0 → 2.55.0.5 | Inno `/VERYSILENT /DIR=D:\Git\Git` (LFS 3.7.1 unchanged) |
| GitHub CLI | 2.98.0 → 2.99.0 | official MSI `/qn` (machine-scope, needed elevation) |
| Bandizip | 7.40.0.1 → 7.46.0.1 | vendor setup `/S` (upgrades in the registered install dir) |
| FreeFileSync | 14.5 (skipped) | see below |

Findings worth keeping:

- **Grok self-update is broken in this layout**: `grok update` reports
  `installer: "npm", error: "program not found"` because the binary lives at
  `D:\GrokBuild\home\bin` (via `GROK_HOME`) instead of the default `%USERPROFILE%\.grok\bin`.
  The official installer script with `GROK_BIN_DIR` pointed at the existing bin dir updates in
  place (and also refreshes the stale `agent.exe`). A stale off-PATH 0.2.112 copy remains at
  `%USERPROFILE%\.grok\bin`; left untouched, documented in curated notes.
- **FreeFileSync cannot be updated in place on the free edition**: the vendor installer
  rejects `/DIR` outside the Business edition (message box: “/dir 安装选项只在FreeFileSync商用版有效”).
  Installing without `/DIR` would create a second copy in the default location, so the update
  was skipped and 14.5 stays recorded.
- **Elevation**: the interactive shell is a split-token admin; gh's machine-scope MSI failed
  with 1603 until the four installer steps (git/gh/bandizip/ffs) ran inside one elevated batch.
  The batch waits for all `D:\Git\Git\*` processes to exit before replacing Git, because every
  Git Bash session locks `msys-2.0.dll`.

## MachineContext changes

- `omp` entity: removed the obsolete `manual-pin` `update_method` and the pin note; new
  curated note states the tool tracks upstream stable via the official updater.
- `grok` entity: curated notes record the working update method and the stale duplicate.
- `bandizip` (supplemental productivity entity): refreshed to 7.46.0.1 with a registry
  evidence entry — routine sync does not re-observe this module (OPERATIONS §8).
- `docs/OPERATIONS.md` §4.2: the "do not run omp update" warning replaced by the current
  policy, including the updater's `.bak` behavior.
- Version drift for command-probed entities (codex-cli, grok, omp, opencodex, pip, uv, uvx,
  git, gh) lands through the normal sync; config profiles (`codex-cli`, `omp`, `opencodex`)
  were checked for `unprojected_keys`/`redactions` after the upgrades — no new entries, the
  18.1.2/0.152.1/2.40.0 releases did not add collected-schema fields to the source configs.
