# Devlog — 2026-10-01 development toolchain refresh

Scope: `uv`/`uvx`, Rust stable + Cargo via the existing `rustup`, Git for Windows, Git LFS,
GitHub CLI, Supabase CLI and Bun — verify the real machine state, compare against official
current stable, upgrade only where a formal stable update exists, keep every existing install
model and root, then publish through the normal sync/validate gates. Explicitly out of scope
and untouched: Node/npm/pnpm, Python, Go, Dart/Flutter, VS/VS Code, MCPorter, agent-browser,
OpenCodex, Lark, Threadripper, and the AI CLIs maintained on 2026-09-30.

Baseline was re-read from the remote rather than from chat: `origin/main` = `4a2adda`.

## Upgrades (before → after, official channel, mechanism)

| Tool | Before → After | Official current stable | Mechanism actually used |
| --- | --- | --- | --- |
| uv / uvx | 0.12.9 → **0.12.21** | GitHub release `0.12.21` (2026-09-29) | `uv self update` — in place at `E:\Dev\uv`, both binaries land on the same version and the same root |
| rustup | 1.29.0 → **1.29.1** | `rustup check` reported 1.29.1 | `rustup self update` — same `%USERPROFILE%\.cargo\bin` root |
| Rust stable (rustc/Cargo) | 1.98.0 → **1.98.1** | `rustup check`: `1.98.0 → 1.98.1 (48a229cea)` | `rustup update stable` on the existing single `stable-x86_64-pc-windows-msvc` toolchain; no Rust was reinstalled and no second toolchain was added |
| GitHub CLI | 2.99.0 → **2.102.0** | `cli/cli` release `v2.102.0` (2026-09-30) | official `gh_2.102.0_windows_amd64.msi` with `msiexec /qn /norestart` inside one elevated process (machine-scope; the interactive shell is a split-token admin) |
| Supabase CLI | 2.116.0 → **2.118.0** | `supabase/cli` release `v2.118.0`; npm `latest` = 2.118.0 | `npm install supabase@2.118.0 --save-dev` into a new versioned prefix directory `D:\Tools\SupabaseCLI\2.118.0`, then one user-PATH segment repointed |
| Bun | 1.4.0 → **1.4.2** | `oven-sh/bun` release `bun-v1.4.2` | official `bun.sh/install.ps1` with `BUN_INSTALL=%USERPROFILE%\.bun`, `-NoPathUpdate -NoRegisterInstallation -NoCompletions` |
| Git for Windows | 2.55.0.windows.5 → **not upgraded** (see below) | `v2.56.0.windows.1` (2026-09-28), non-prerelease | blocked by the installer's own running-process pre-check |
| Git LFS | 3.7.1 → **unchanged** | upstream `v3.8.0` | bundled copy inside Git for Windows, so it only moves with that installer |

Already latest, so nothing was done: nothing in this batch — every target except Git/LFS had a
real stable update available.

## Git for Windows: verified blocker, not an assumption

`Git-2.56.0-64-bit.exe` (sha256 `BFE94E7B419B16EEE9FECBD1253A98E3D4F49BA8F029630549052278FFE286A6`,
Authenticode **Valid**, signer `CN=Johannes Schindelin` — the official GfW signer) was run as
`/VERYSILENT /NORESTART /SUPPRESSMSGBOXES /DIR=D:\Git\Git` from an elevated process. It exited 1
after about two seconds. The Inno log states the reason:

```
Defaulting to Cancel for suppressed message box (Retry/Cancel):
The following process(es) use Git for Windows:
bash.exe (PID ...)  bash.exe (PID ...)  tail.exe (PID ...)
Please terminate those processes and retry.
```

Two things worth recording:

- The abort is **clean**. Every probed file (`cmd\git.exe`, `mingw64\bin\git.exe`,
  `mingw64\bin\git-lfs.exe`, `usr\bin\msys-2.0.dll`, `usr\bin\bash.exe`, `etc\gitconfig`) kept
  its exact size, mtime and version, `Git_is1 DisplayVersion` stayed `2.55.0.5`, and `git --version`,
  `git lfs version`, the `filter.lfs.*` system-config registration and a repo `status`/`push` all
  still worked afterwards. No mixed tree, no repair needed.
- This is why the 2026-09-02 round's elevated batch *waited* for `D:\Git\Git\*` processes to exit:
  the installer offers only Retry/Cancel and has no silent override flag. Any agent session that
  keeps a persistent Git Bash shell alive therefore cannot upgrade Git from inside the session —
  the lock is not `msys-2.0.dll` being unwritable in principle, it is the installer refusing to
  proceed at all while a consumer process exists. `winget upgrade Git.Git` was deliberately not
  tried as a workaround: that package installs the same Inno executable, so it hits the same gate
  (inference from the shared installer, not observed this round).

Follow-up for a future round: run the vendor installer when no Git-for-Windows process is alive
(e.g. from an elevated plain PowerShell window with the agent session closed). The
signature-verified 2.56.0 installer and a signature-verified 2.55.0.5 rollback package are both
kept under `.local/installers/`. Because LFS ships with Git, `git-lfs` stays at 3.7.1 until that
window exists too; installing upstream `git-lfs` 3.8.0 standalone would create a second copy and
was rejected.

## Command resolution and install-model checks

`Get-Command` / persistent-PATH simulation after the updates:

- `uv`, `uvx` → `E:\Dev\uv\uv.exe`, `E:\Dev\uv\uvx.exe` (unchanged root; `uvw.exe` updated with them).
  The root now holds two `.uv.*.__selfdelete__.exe` leftovers — one per `uv self update`, vendor
  behaviour, left alone (same class as OMP's `omp.exe.*.bak`).
- `rustc`, `cargo`, `rustup` → `%USERPROFILE%\.cargo\bin\*` (rustup proxies, unchanged);
  `rustup toolchain list` still shows exactly one toolchain.
- `gh` → `%PROGRAMFILES%\GitHub CLI\gh.exe`. `%LOCALAPPDATA%\GitHub CLI\hosts.yml` and `config.yml`
  do not exist on this machine, i.e. gh was never authenticated here, so the MSI upgrade had no
  sign-in state to disturb. No extensions directory.
- `supabase` → `D:\Tools\SupabaseCLI\2.118.0\node_modules\.bin\supabase.cmd` (`path_index` 34 in
  canonical is unchanged). The user PATH edit replaced **exactly one** segment (index 17 of 28),
  kept `REG_EXPAND_SZ` (`ExpandString`) and the literal `%USERPROFILE%\.dotnet\tools` token, and
  appended nothing; `2.109.1` and `2.116.0` directories were left in place per the existing model.
- `bun` → `%USERPROFILE%\.bun\bin\bun.exe`, with `bunx.exe` updated alongside it; user PATH, the
  `HKCU\...\Uninstall\Bun` entry and the PowerShell profile all verified untouched (both profile
  paths remain absent).

Smoke tests (light, as scoped): `uv --help`, `uvx --version`, `rustup run stable rustc --version`,
`cargo --version`, `gh --version` + `gh config list --help`, `supabase --version`,
`bun -e 'console.log(1+1)'`, `bunx --version`, `git --version`, `git lfs version`,
`git lfs env` (endpoint resolves for this repo), repo `status --porcelain` clean.

## Node 24 check

Nothing in this batch was skipped for a Node engine floor. `npm view supabase@2.118.0 engines`
returns nothing (no engine declared) and its platform packages are Go binaries, so Node 22.23.2
remains sufficient. Node itself was not touched, per scope. (The pre-existing Node-24 pin that
holds `mcporter` at 0.9.0 is unchanged and out of scope.)

## Canonical

- Routine providers refreshed the version fields for `uv`, `uvx`, `rustc`, `cargo`, `rustup`, `gh`,
  `bun`, plus the `supabase` version, `executable`, `install.root` and its `command_resolution`
  entry; `context/machine.json` carries the matching user-PATH segment (three views) and D:/E:
  free-byte drift. Git and Git LFS records are unchanged, which is the honest reading.
- Four curated notes were added (`supabase`, `git-lfs`, `git`, `bun`) recording the durable
  install/update models rather than this round's numbers; the `git` note replaced a first draft
  that described the msys lock as folklore and now states the observed installer behaviour.
- The user-scope half was published first (`14aeeb0`) as a deliberate safety net, before the
  elevated Git attempt that could have disturbed the `git` used for committing and pushing.

## Gates

- `tests/run-tests.ps1` not run: no collector, lib or test change this round (OPERATIONS §2.3
  gate 1 makes it conditional on exactly that).
- `sync.ps1`: all providers success, validation ok, 0 warnings.
- `validate.ps1`: `errors`, `warnings`, `findings` all empty.
- Diff review line-by-line: only target versions/paths, the four curated notes, heartbeat and
  free-space drift. One tooling defect found and fixed during this round: the first curation pass
  used `@(Get-McObjectPropertyOrNull … notes)` on an absent property, which yields `@($null)`, so a
  `null` element was written into four `notes` arrays; a follow-up pass stripped it and the
  published diff now contains the note strings only.
- Privacy sweep over added diff lines: no credential shapes, no literal account path, no URLs; the
  single pattern hit was the phrase "split-token admin" in the `git` note.
- Second sync idempotent apart from the `context/status.json` heartbeat.
