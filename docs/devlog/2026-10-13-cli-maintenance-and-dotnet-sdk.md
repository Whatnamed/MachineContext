# Devlog — 2026-10-13 CLI incremental maintenance and project-local .NET SDK record

Scope: upgrade the AI/developer CLIs that still had an official stable release past the
recorded baseline, using each tool's existing install root and recorded upgrade mechanism;
light incremental patrol over the remaining commonly used CLIs; complete the .NET record so
the machine's usable SDK is visible without promoting a project-local SDK to a system SDK;
then run the OPERATIONS gates. Machine changes were only recorded when they actually
happened.

## Upgrades (before → after, official release evidence, mechanism actually used)

| Tool | Before → After | Official release evidence at execution time | Mechanism |
| --- | --- | --- | --- |
| **OMP / Oh My Pi** | 18.8.7 → **18.10.3** | GitHub `can1357/oh-my-pi` latest non-prerelease `v18.10.3`, published 2026-10-12T19:23:53Z | `omp update` — native updater replaced `D:\OMP\omp.exe` in place; sha256 `C7969E65AB75AA9AE6F93F0FA8307C9FE8DC4CD2AD5CCD5BFA282ED8C840A7D5`, 225,642,496 → 244,256,768 B, matching the hash the updater verified |
| **Codex CLI** | 0.162.0 → **0.162.1** | npm dist-tag `latest = 0.162.1` (stale `beta`/`native`/`release-0.159.0-alpha…` tags and the alpha line ignored) | `npm install --prefix E:\Codex\codex-cli @openai/codex@0.162.1`; prefix `package.json` now `^0.162.1`, `codex.cmd` shim unchanged |
| **Claude Code** | 2.1.295 → **2.1.296** | npm `latest = 2.1.296`, `next = 2.1.296`, `stable = 2.1.287` — `stable` is again older than `latest`, so `latest` remains the tracked lineage | `npm install --prefix D:\Claude\cli @anthropic-ai/claude-code@2.1.296`; `claude.cmd` unchanged |
| **Grok Build CLI** | 1.0.50 → **1.0.52** | the product's own check: `grok update --check --stable` → `A new version of Grok Build is available: 1.0.50 -> 1.0.52 [stable]` | `grok update --stable` in place at `D:\GrokBuild\home\bin` (also refreshed `agent.exe` and the `grove*.exe` helpers; parked `grok.exe.old`) |
| **uv / uvx** | 0.12.24 → **0.13.0** | GitHub `astral-sh/uv` `0.13.0`, published 2026-10-09T19:49:55Z (still latest; no 0.13.1 exists) | `uv self update` in place at `E:\Dev\uv`; both binaries report `0.13.0 (4ecd0eff2 2026-10-09)` |
| **Lark CLI** | 1.0.64 → **1.0.97** | npm `latest = 1.0.97`, `engines.node >= 16` | `npm install -g @larksuite/cli@1.0.97` in the existing global prefix `E:\Dev\npm-global` |
| **Agy** | recorded 1.3.2 → actually **1.3.3** | GitHub `google-antigravity/antigravity-cli` `1.3.3`, published 2026-10-10T03:06:26Z | **No action taken.** The binary was already 1.3.3 (`%LOCALAPPDATA%\agy\bin\agy.exe` mtime 2026-10-11T19:07+08:00, before this round), the user reports updating the Antigravity desktop app in that window, and `agy update` answered "You are already on the latest version." with the bytes unchanged. Canonical caught up to the machine, not the other way round. |

## uv 0.13.0: why the breaking changes were accepted

`0.13.0` makes Python 3.15 the default stable version and changes constraint handling. Each
item was checked against the machine before upgrading rather than assumed:

- **default Python 3.15** applies only when nothing is requested/pinned *and* no suitable
  interpreter exists. Both uv projects here (`E:\Projects\agent-bridge\agent-bridge\monitor`,
  `E:\Projects\agent-bridge-legacy\monitor`) carry `.python-version` = `3.10` with
  `requires-python >= 3.10` and their own `.venv`, and a managed `cpython-3.10.21` is already
  installed. After the upgrade, `uv python find` in an empty scratch directory still resolves
  that 3.10.21 — no 3.15 was pulled — and `uv python list --only-installed` still shows exactly
  `cpython-3.12.10` (D:\Python) plus `cpython-3.10.21`.
- **`--require-hashes` honored / editable requirements rejected in included constraints**: a
  bounded search found one plain `requirements.txt` (`E:\Projects\小说爬取实验`, unpinned ranges,
  no hash directive) and no `require-hashes` anywhere under E:\Projects, E:\Dev or D:\Morpho.
- **Windows ARM64 native-preference**: not applicable, this host is x86_64.
- **`uv_build` backend bound**: no project uses it (both monitor projects use
  `setuptools.build_meta`), and there is no `uv.toml` (checked `%APPDATA%\uv`,
  `%USERPROFILE%\.config\uv`, `E:\Dev\uv`) and no `UV_*` variable to migrate.
- **`uvx` is not referenced by any MCP server source** in `context/configs/mcp.json`, so agent
  tool startup does not depend on uv's resolver behaviour.
- Post-upgrade functional check: `uv lock --check --offline` against a scratch copy of the
  pinned monitor project resolved its 68 packages with exit 0.

Known pending cost from the release notes, not incurred during this round: 0.13.0 reformatted
many cache entries, so the next real install may re-download or rebuild wheels once.
`%LOCALAPPDATA%\uv\cache` was left alone.

## OMP 18.10.0 Windows IPC change (checked specifically)

The release note for `v18.10.0`: local IPC endpoints (daemon broker, LSP mux, IDA hosts, text
prediction, `omp stream`, Collab discovery, local model workers) moved to a native owner-only
transport **including Windows named pipes**, and *on Windows daemons started by an older omp are
not reused, so older sessions must be closed after upgrading*.

- `Get-Process omp` was 0 both before the update and after it, so no live session had to be
  closed and none was interrupted (checked together with agy/codex/claude/grok/dsh, all 0).
- Post-upgrade, the first `omp -p` run created a new endpoint directory
  `~\.omp\run\daemons\eabb51da4a49a424` (11:11) while the 18.8.7-era
  `~\.omp\run\daemons\d83b5a8af390f473` directory (01:16) stayed untouched — no cross-version
  daemon was reused. Those leftover directories are harmless; 18.10.0 also implements
  stale-endpoint takeover.
- **Evidence limit**: enumerating `\\.\pipe\` during a live run produced no
  `omp`/`broker`/`predict`/`lsp` match, so the named-pipe transport itself is taken from the
  upstream note plus the endpoint-directory behaviour, not from a direct handle sighting.
- Model configuration and context rules: `config.yml` (sha256 `3C10B7BA…`) and `models.yml`
  (sha256 `2EF61834…`) byte-identical before and after; `enabledProviders` still `["codex"]`,
  `modelRoles` still `{"default":"google-antigravity/gemini-3.8-flash","web":"web/parallel"}`,
  `shellPath` `D:\Git\Git\bin\bash.exe`, `defaultThinkingLevel` `auto`. `models.yml` was
  re-examined rather than assumed because `18.9.2` stopped bare model IDs there from resolving
  to auto-discovered Ollama/llama.cpp/LM Studio providers; the custom TokenRhythm provider is
  byte-unchanged. Global-rules load re-verified on 18.10.3 by **verbatim** enumeration from a
  scratch repo containing only `.git`: the six user-global Chinese headings came back
  (`%USERPROFILE%\.codex\AGENTS.md` still reaches the model).

## Light patrol results

| Tool | Installed | Official latest at execution time | Action |
| --- | --- | --- | --- |
| Lark CLI | 1.0.64 | npm `1.0.97` | upgraded (above) |
| Grok Build CLI | 1.0.50 | `1.0.52` via its own `--check` | upgraded (above) |
| DSH | 0.2.0-rc.2 | npm `@deepseek-ai/dsh` latest `0.2.0-rc.2` | already latest; the `dsh` command is owned by the Desktop payload |
| GitHub CLI | 2.102.0 | GitHub `v2.102.0` | already latest |
| Git for Windows | 2.56.0.windows.2 | `v2.56.0.windows.2` | already latest |
| Git LFS (bundled) | 3.8.0 | `v3.8.0` | already latest; version follows the Git installer |
| Supabase CLI | 2.120.0 | `v2.120.0` | already latest |
| OpenCLI | 1.8.8 | npm `1.8.8` | already latest |
| Agently CLI | 1.0.18 | npm `1.0.18` | already latest |
| Codex Threadripper | 0.3.6 | npm `0.3.6` | already latest |
| PowerShell | 7.6.6 | native MSI baseline from 2026-10-10 | unchanged |
| MCPorter | 0.9.0 | npm `0.14.3`, still `engines.node >= 24` | **not upgraded by decision**: the machine runs Node 22.23.2 and Node was deliberately not moved for this tool (recorded 2026-09-26). A 2026-10-13 re-check note was appended. |
| OpenCodex | 2.64.0 | npm `2.84.0` | **not upgraded by decision**: `curated.status = inactive` since 2026-09-15; reviving or updating it is out of scope. |
| Agent Reach | 1.5.0 | upstream installs from the GitHub `main` archive, and `check-update` cannot distinguish 1.5.0 builds | not reinstalled this round; deciding would require the file-by-file content comparison recorded 2026-09-26 |
| Runtimes (Node 22.23.2, Python 3.12.10, Go 1.26.7, Rust 1.99.0, Bun 1.4.2) | — | newer official releases exist for some | **out of scope**: these are runtimes/toolchains, not CLI maintenance targets; upgrading Node or Python is a migration in its own right and none was requested |
| Desktop apps (VS Code, Cursor, Unity Hub, Tera Term, Qoder, WorkBuddy, ZCode, Codex/Claude Desktop…) | — | — | not touched; routine scan does not refresh supplemental desktop entities (OPERATIONS §8), and the task scoped this round to CLIs. Codex Desktop did move by itself (see drift below). |

`rustup check` printed a self-contradictory `stable … update available: 1.99.0 (b940084d7) -> 1.99.0 (b940084d7)`
and `rustup - up to date : 1.29.1`; no Rust action was taken and the odd line is not evidence
of a newer compiler.

## .NET: what was verified and what was recorded

Read-only verification first, before writing anything:

- `%PROGRAMFILES%\dotnet\dotnet.exe --list-sdks` exits 0 with **zero** SDK entries; recorded
  runtimes stay 6.0.26 / 7.0.0 / 8.0.21. So there is still no system SDK, and that system probe
  fact was not overwritten.
- `E:\Projects\CS2-Local-Kit\CS2-Local-Kit\temp\tooling\dotnet\dotnet.exe` → `--version` and
  `--list-sdks` report SDK `10.0.401` from `…\temp\tooling\dotnet\sdk`; `--list-runtimes`
  reports `Microsoft.NETCore.App`, `Microsoft.AspNetCore.App` and
  `Microsoft.WindowsDesktop.App` all `10.0.12`. The three components a consumer actually needs
  all exist: `sdk\10.0.401\Sdks\Microsoft.NET.Sdk.WindowsDesktop\Sdk\Sdk.props`,
  `packs\Microsoft.WindowsDesktop.App.Ref\10.0.12\ref\net10.0\PresentationFramework.dll`,
  `shared\Microsoft.WindowsDesktop.App\10.0.12\PresentationFramework.dll`.
- Nothing was downloaded, installed, copied or moved; PATH untouched; AgentBench configuration
  untouched; the AgentBench construction matrix was not re-run.

Reuse mechanism read from AgentBench (`E:\AgentBench\AgentBench`):
`config.local.json` sets `dotnet_executable` to exactly the SDK above, and
`scripts/dotnet_toolchain.py` re-validates `10.0.401`, the `10.0.12` WindowsDesktop targeting
pack and shared runtime, and the x64 PE header before every run, then confines `DOTNET_ROOT`,
`DOTNET_CLI_HOME`, `NUGET_PACKAGES`, `NUGET_HTTP_CACHE_PATH` and `TEMP/TMP` into its own
`.scratch` directories. `docs/P1-B2-readiness.md` states the policy in words: reuse this
existing SDK, no system-host fallback, no repeat install.

Record state found and carried forward: the 2026-10-12 session had already added the
`dotnet-sdk` entity and its devlog **but left them uncommitted in the working tree**
(`CURRENT.md`, `context/software/development.json`, the untracked devlog). Nothing was
discarded or rewritten; this round verified that record, kept its content, and appended only
what was missing.

Canonical edits, all through the OPERATIONS §6 route with the repo JSON helpers:

- `dotnet-sdk` (project-local scope, `install.scope = project`, refresh policy
  `manual-targeted-toolchain-verification`) — not registered as a system SDK, and its `curated`
  now also carries the 2026-10-13 re-verification and the AgentBench consumption path.
- `dotnet` (system host) — `curated.notes` records that the runtime-only host is a property of
  that installation, that "no system SDK" is not "no usable SDK", and points at `dotnet-sdk`.
- **Ownership outcome worth knowing**: `dotnet.observed.verification_note` is collector-owned,
  and the 2026-10-13 sync legitimately reverted the 2026-10-12 rewrite of it back to the
  collector's own string (`dotnet --version is unavailable because no .NET SDK is installed;
  runtimes were checked separately`, `scripts/collectors/host-tool-verifiers.ps1:343`). That is
  correct per the collector-owned-observed rule, so the qualification lives in `curated`
  instead. The collector string is still worded absolutely and would read as a machine-wide
  claim to a consumer that ignores `scope`; changing that string is a collector change with its
  own test surface and was left for a task that explicitly takes on collection logic.
- No `relationships.json` edge was invented: `provided_by` is the only relation in use and an
  SDK is not "provided by" a runtime-only host.

## Preservation

SHA-256 captured before the first upgrade and after the last (full record:
`.local/config-hashes-2026-10-13-before.txt`, re-check in `.local/verify-2026-10-13.txt`).
Byte-identical across the round: `.gemini\config\GEMINI.md`,
`.gemini\antigravity-cli\settings.json`, `.gemini\config\mcp_config.json`,
`.claude\CLAUDE.md`, `.claude\settings.json`, `.claude.json`, `.codex\AGENTS.md`,
`.omp\agent\config.yml`, `.omp\agent\models.yml`, `.gitconfig` (per-URL proxy
`http://127.0.0.1:7988` for github.com plus the `gh` credential helpers) and
`D:\GrokBuild\home\config.toml`. OMP `agent.db` / `.env` / `history.db` were never read and are
still present; Codex `auth.json` and `sessions\` untouched. No npm/npm-global config, no PATH,
no proxy setting was modified.

Smokes: `omp -p` → OK; `codex exec --skip-git-repo-check` → OK; `claude -p` → OK (pre-existing
`unrecognized_model` notice for `deepseek-v4-pro[1m]`); `grok -m dasu -p` → OK and `grok inspect`
still resolves the global ruleset with 52 skills; `lark-cli --version` → 1.0.97; `uv python find`
and `uv lock --check` as above. No agent session was interrupted — none was running.

## Pass-through drift (not caused by this round)

- **Codex Desktop** `26.1002.7124.0 → 26.1007.2314.0` (background vendor update), which also
  moved its `cua_node` runtime directory `3dd31cfff853001c → cfb32733c877621e`; both flow into
  `context/software/ai.json` and `context/configs/mcp.json` automatically.
- **Codex CLI config projection**: `model gpt-6.1-sol → gpt-6-astra` and
  `model_reasoning_effort medium → xhigh`. `config.toml` was rewritten twice today, at 10:23:27
  (before any action in this session) and again at 11:18:24; the CLI and the Desktop share this
  file, and these are preference keys the npm install does not write. Published as observed
  drift, with the attribution limit stated in the `codex-cli` curated note rather than claimed
  as provenance.
- **qoder** `mcp-router.json` `exists: false → true`: expected — it is a runtime file the desktop
  process writes while running.
- Disk free space moved materially on all three drives since the 2026-10-10 snapshot
  (C: 12.5→11.5, D: 19.8→8.5, E: 126.0→86.0 GiB), largely other agents' work.

## Publishing process notes

- `sync.ps1 -RepoRoot "E:\MachineContext" -AllowDirty` ran with all 10 providers `success` and
  published atomically; the dirty working tree was the 2026-10-12 .NET work plus this round's
  curated edits, both part of this workflow, so `-AllowDirty` was the documented option rather
  than a workaround.
- `lark-cli` has no routine provider (it is in `meta.supplemental_inventory.entity_ids`), so its
  version had to move through the §6 route; the same route recorded its upgrade note.
- Pitfall for the next session: `curated.notes` on software entities is an **array** everywhere
  except the two .NET records written in 2026-10-12/13, which used a bare string. Both are now
  arrays. The one-off scripts are `.local/curate-dotnet-2026-10-13.ps1`,
  `.local/refresh-lark-2026-10-13.ps1` and `.local/curated-2026-10-13-cli-maintenance.ps1`
  (all single-use). Order matters for a post-mortem: the first script converted `dotnet` to a
  *string* note and merged today's .NET facts into the existing `dotnet-sdk` string; the third
  script normalized both records to arrays, restored the untouched 2026-10-12 sentence as
  `dotnet-sdk` element 1, and split the 2026-10-13 facts into their own elements. Removing the
  resulting duplicate undated `dotnet` note took one further `Set-McObjectProperty`-style
  edit through `scripts/lib/json.ps1`, which is why the third script resets
  `$dotnet.curated.notes` before appending. The `dotnet-sdk` block asserts the pre-fixup string
  shape and will now throw rather than double-append; the CLI notes are exact-match deduped, so
  re-running those is a no-op. None of these scripts should be treated as re-executable.
- Two scripts also had to be re-run after `Set-StrictMode -Version Latest` in `scripts/lib/runtime.ps1`
  rejected `.Count` on an empty pipeline result and `curated.PSObject.Properties.Name` on a
  property-less object; use `@(...)` and `PSObject.Properties['name']` in `.local` helpers.
- `Set-McObjectProperty` (`scripts/lib/json.ps1`) does **not** accept pipeline input; call it with
  `-InputObject`.

## Not done / open items

- uv's cache reformat cost is still pending (first real install after 0.13.0 may re-download).
- `mcporter` stays at 0.9.0 until Node moves to ≥24; that migration is a separate task.
- The `host-tool-verifiers.ps1` absolute wording for `dotnet` remains as described above.
- AgentBench is consumed by this machine context (it pins the project-local SDK) but is not in
  `context/projects/`; registering it was outside this round's scope.
