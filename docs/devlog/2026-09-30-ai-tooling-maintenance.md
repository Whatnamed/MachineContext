# Devlog — 2026-09-30 AI / Agent tooling maintenance (upgrades, DSH command ownership, Kimi Code intake)

Scope: audit the real machine state for the AI/agent CLIs, bring the ones that are actually behind up to official stable latest in place, resolve who owns the `dsh` command now that the official DSH Desktop is installed, intake the newly installed Kimi Code, and publish the result. Explicitly out of scope (by instruction): Lark CLI, Agently CLI, MCPorter, agent-browser, OpenCodex, Agent Reach, OpenCLI, Codex Threadripper, and any Node major migration.

Two premises in the task brief turned out to be wrong against the machine, and the record follows the evidence rather than the brief:

1. **Kimi Code on this machine is a desktop app, not the `kimi` CLI.** No `kimi` command exists anywhere; see section 6.
2. **Agy was already on 1.2.14** before this session started, so it needed a canonical catch-up, not an upgrade; see section 5.

## 1. Upgrade results

| Tool | Before → After | Mechanism actually used | Executable (unchanged?) |
| --- | --- | --- | --- |
| Codex CLI | 0.156.1 → **0.159.2** | `npm install --prefix E:\Codex\codex-cli @openai/codex@0.159.2` | `E:\Codex\codex-cli\codex.cmd` (unchanged) |
| OMP / Oh My Pi | 18.3.0 → **18.4.4** | `omp update` (native self-updater, stable) | `D:\OMP\omp.exe` (unchanged) |
| Grok Build CLI | 1.0.41 → **1.0.44** | `grok update` (native self-updater, stable) | `D:\GrokBuild\home\bin\grok.exe` (unchanged) |
| Claude Code | 2.1.281 → **2.1.285** | `npm install --prefix D:\Claude\cli @anthropic-ai/claude-code@2.1.285` | `D:\Claude\cli\claude.cmd` (unchanged) |
| Agy | 1.2.11 (recorded) → **1.2.14** (already installed) | none — canonical catch-up; `agy update` confirms latest | `%LOCALAPPDATA%\agy\bin\agy.exe` (unchanged) |
| DSH CLI | 0.1.5-rc.2 at `D:\DSH` → **0.2.0-rc.2, Desktop-provided** | official in-product command manager (see section 4) | **changed** to `D:\DSH-desktop\resources\runtime\cli\bin\dsh.cmd` |
| Kimi Code | not recorded → **1.0.4 desktop app** | user-installed before this round | new entity, no command |

Stable/latest was re-checked at execution time rather than taken from the brief:

- **Codex** — npm `latest: 0.159.2` (`alpha: 0.161.0-alpha.4` not used).
- **Claude Code** — npm `latest: 2.1.285`, `stable: 2.1.280`, `next: 2.1.285`. `stable` is *again* older than `latest`, re-confirming the 2026-09-25 caveat that "stable latest" must be disambiguated. The existing install's provenance is the default dist-tag, so `latest` was installed.
- **OMP** — `omp update --check` reported 18.4.4 and upstream GitHub latest non-prerelease is `v18.4.4` (published 2026-09-29T19:35:17Z).
- **Grok** — `x.ai/cli/stable` → `1.0.44`; `x.ai/cli/alpha` → `1.0.45` (not used). `grok update --check` agreed: `1.0.41 -> 1.0.44 [stable]`.
- **Agy** — GitHub latest non-prerelease `1.2.14` (published 2026-09-30T04:03:27Z); machine already on it.
- **DSH** — npm `@deepseek-ai/dsh` `latest: 0.2.0-rc.2`, and the Desktop's own electron-updater feed (`download.deepseek.com/dsh-desk/feeds/win-x64/`, channel `nightly`) reports `0.2.0-rc.2` (2026-09-29T10:35Z). Installed Desktop is current.
- **Kimi Code** — feed `code.kimi.com/kimi-code/desktop/` channel `latest` reports `1.0.4` (2026-09-24T07:47Z). Installed app is current.

## 2. Codex: CLI upgraded without touching the Desktop runtime

The protection condition was verified before any write, because the historical `CODEX_CLI_PATH` claim needed re-testing rather than trusting:

- `CODEX_CLI_PATH` is **not** a process or user environment variable. The only `CODEX*` env var set is `CODEXOMETER_LANG`.
- `CODEX_CLI_PATH` exists exactly once, inside `%USERPROFILE%\.codex\config.toml` under `[mcp_servers.node_repl.env]`, pointing at the **Desktop-provisioned** versioned binary `%LOCALAPPDATA%\OpenAI\Codex\bin\c6fe824d725f02d7\codex.exe` (mtime 2026-09-30T17:17, written by the Desktop itself).
- `config.toml` contains **no reference at all** to `E:\Codex\codex-cli`.

So the standalone CLI and the Desktop runtime are independent, and the upgrade could not redirect the Desktop. Nothing under `%USERPROFILE%\.codex` was reset, and the AppX/MSIX payload was not touched.

Preservation and smoke:

- `config.toml` was byte-identical before the install, after the install, and after `codex exec` (sha256 `7B86469D…CCDA7298` **at that time**); `AGENTS.md` unchanged (`A9829D5C…97BB9229`). Later the same evening the user/Desktop edited `config.toml` again (`model_reasoning_effort` went back to `high`), so that hash is an upgrade-window fingerprint, not a current one — the canonical note says so explicitly rather than quoting a stale hash bare.
- `where.exe codex` → `E:\Codex\codex-cli\codex{,.cmd}`; `codex --version` → `codex-cli 0.159.2`; `codex --help` ok.
- `codex exec --skip-git-repo-check "Reply exactly: OK"` → `OK`, exit 0.
- **Desktop smoke:** Codex Desktop 26.928.2636.0 was *already running* across the upgrade (12 `ChatGPT.exe` processes plus its own bundled `codex.exe`). Its window was inspected directly: it renders normally, the pinned and project session lists are intact (opencodex / 清盘 / Morpho threads, MachineContext, ProxyLens, agent-bridge, …), and a user task was actively mid-run ("正在思考"). Because real in-flight work was visible, **no new session was forced** — the running task plus intact runtime is the initialization evidence, and creating a session would have disturbed the user's work. The Desktop runtime path was still its own bundled binary afterwards.
- Left alone as pre-existing: the unrecognized `disable_response_storage` warning, and a `cloudflare-api` MCP OAuth `invalid_grant` refresh error unrelated to this round.

Routine drift recorded from the same sync, not caused here: `codex-desktop` auto-updated 26.917.9434.0 → 26.928.2636.0, which also moved the `cua_node` runtime hash and the `cua_repl` AppX command path in `mcp.json`.

## 3. OMP, Grok, Claude, Agy — config and rules preservation

**OMP.** No session was running, so no lock had to be released. `D:\OMP\omp.exe` replaced in place, sha256 `5644E5D7…D41A3F54`, matching the hash the updater verified. `config.yml` (`3C10B7BA…AABDC785`) and `models.yml` (`2EF61834…8A229C092`) were **byte-identical** before and after; `enabledProviders` is still `["codex"]`, `modelRoles.default` still `google-antigravity/gemini-3.8-flash`, TokenRhythm intact; `agent.db` / `.env` / `history.db` were never read. Global-rules live-load re-verified on 18.4.4 the way the 2026-09-16 lesson requires — **verbatim enumeration**, not a model-reported count: from a scratch repo containing only `.git`, `omp -p` listed the six user-global Chinese headings (沟通 / 任务执行 / 仓库与本机环境 / 测试与验证 / Git / 完成与汇报).

One **correction** to the standing note: the updater keeps only the *most recent* backup. After this update `omp.exe.1790270148771.31792.0.bak` (18.2.1) is gone and only the 18.3.0 backup remains. The 2026-09-25 note claimed both were still present.

Profile drift in the same sync, from the user's own 2026-09-29 config edit (not from the upgrade): `providers.webSearchOrder` is no longer in `config.yml` — it was replaced by `modelRoles.web: web/parallel` — so the projection loses `webSearchOrder` and gains `web`. Two new unprojected keys appeared, `omp.config.retry` and `omp.config.compaction`. Both were checked against the §4.2 "is this a load-bearing field we are missing?" test and are behaviour tuning, not the context-source gate; `enabledProviders` remains projected, so the load-bearing field is still covered.

**Grok.** `D:\GrokBuild\home\config.toml` was **not rewritten at all** this round (byte-identical, sha256 `6681C2D9…59506D03`, 6639 B), unlike the 1.0.41 update's TOML round-trip — so `[cli] installer = "internal"` and every model/MCP/skill table survived by construction, and no diff analysis was needed. `grok.exe` and `agent.exe` turned out to be byte-identical to each other (same sha256 and size): one binary installed under two names. `grok inspect` still resolves the global personal ruleset from `%USERPROFILE%\.claude\CLAUDE.md` via Claude Code compatibility with 52 user-scope skills.

`grok -p` **fails**, and the round records why that is not an upgrade regression: on the default model `grok-4.5` it returns `403 GROUP_DELETED: API Key 所属分组已删除` from the `https://api.aijws.com` gateway. A/B control on the same unchanged config — the updater-parked 1.0.41 binary (`grok.exe.old`) fails identically, while `grok -m dasu -p "Reply exactly: OK"` on 1.0.44 returns `OK` exit 0. So the defect is the gateway-side deletion of that API key group. No credential was read or modified, and no provider config was changed to work around it.

**Claude Code.** Command resolution unchanged; `%USERPROFILE%\.claude\CLAUDE.md` byte-identical (`17CDB0FE…51F52BE1`), `skills` (10 dirs) and `.claude.json` untouched by the install. `claude -p` → `OK`, still printing the pre-existing `[claude-code:unrecognized_model]` notice for the configured `deepseek-v4-pro[1m]` alias.

**Agy.** Canonical catch-up, **not** an upgrade performed here: the machine was already on 1.2.14 while canonical recorded 1.2.11. `E:\AGY\cli\agy.exe` mtime 2026-09-30T19:42 with the updater-parked `agy.exe.1790768416625916700.old` (itself installed 2026-09-28T13:34) still present, so the replacement happened outside this session. `agy update` printed `Checking for updates... (current version 1.2.14)` / `You are already on the latest version.` and exited 0. Resolution is unchanged (`%LOCALAPPDATA%\agy\bin` is still a directory junction to `E:\AGY\cli`). Live-load re-verified on 1.2.14: from a scratch git repo with no `AGENTS.md`/`GEMINI.md`, `agy -p` answered `E:\MachineContext\CURRENT.md`, a path that appears only in `%USERPROFILE%\.gemini\config\GEMINI.md`. No duplicate `%USERPROFILE%\.gemini\GEMINI.md` was created. Note the `.old` file survived this time where the 2026-09-19 run reported the updater deleting its own — updater housekeeping is not stable, so a leftover `.old` is not evidence of a manual copy.

## 4. DSH: command ownership resolved to the official Desktop, no data migration

The brief's framing was correct and was followed: this was about **who provides `dsh`**, not about moving `%USERPROFILE%\.dsh`.

Findings before any change:

- DSH Desktop is `DeepSeek Harness 0.2.0-rc.2` at `D:\DSH-desktop` (HKCU uninstall key `1bf39983-50d0-5fe0-9ef4-cece76f67c5e`), installed 2026-09-29. Its install root also carries a `version` file containing `44.0.0` — the **Electron shell version**, not the product version (a §8-class trap, now written down).
- The Desktop ships its own CLI launcher `resources\runtime\cli\bin\dsh.cmd`, which runs `@deepseek-ai\dsh-desktop-host\lib\cli.js` from `app.asar` under `ELECTRON_RUN_AS_NODE=1`. Verified working: it prints `0.2.0-rc.2` and exposes the same profile-launcher surface as the retired CLI.
- Command ownership is implemented in-product: `command-manager.js` spawns `command-path.ps1` on win32 with an `inspect` / `install <fingerprint>` / `remove <fingerprint>` request. `install` **prepends** the launcher directory to the persistent user PATH and records ownership under `HKCU\Software\DeepSeekHarness\Command` — it copies no shim and never touches the Machine PATH. `HKCU\Software\DeepSeekHarness` did not exist, i.e. the user had not yet used the menu.
- `HKCU\Software\DeepSeekHarness` absent + `where.exe dsh` → `D:\DSH\dsh.cmd` meant the old 0.1.5-rc.2 install was still authoritative.

Because the shipped worker *is* the code the GUI menu invokes, and it fixes its own `directory` argument (no caller-supplied path), calling it directly was the reliable official equivalent rather than a fragile GUI simulation. `inspect` returned fingerprint `d6231031…12cd0316`; `install` with that fingerprint succeeded:

- `managed: true`, `activeCommand: D:\DSH-desktop\resources\runtime\cli\bin\dsh.CMD`, `available: true`.
- Diffed against a saved copy of the user PATH: exactly **one entry added** (prepended), **nothing removed** by the installer.
- `WM_SETTINGCHANGE` broadcast so new shells pick it up.

Then the stale `D:\DSH` PATH entry was removed (preserving the `REG_EXPAND_SZ` kind), so `where.exe dsh` and `Get-Command dsh -All` return **only** the Desktop launcher. Every other command was re-checked afterwards and still resolves to the same path (`codex`, `omp`, `grok`, `claude`, `agy`, `git`, `node`).

**`D:\DSH` was not deleted.** It is not just the old CLI: besides `node_modules` it holds user files the Desktop payload does not contain (`dsh-launcher.exe`, `dsh-tray.ps1`, `community-presets\`, `backup\`, `logs\`, and a downloaded `DSH-Desktop-2.0.0-x64-Setup.exe`). Only its command/PATH ownership was retired. The exact pre-change PATH values are saved in `.local\user-path-before-dsh-switch.txt` and `.local\user-path-before-dsh-entry-removal.txt` for restoration.

Shared-home verification (nothing to migrate): `%USERPROFILE%\.dsh` is still the single data home. The Desktop bootstrapped `profiles\desktop` inside it and touched `.credentials.yaml` at 2026-09-29T22:18, without disturbing `.agent-presets`, `storages\`, `sessions\` or `AGENTS.md`.

Rules continuity: `@deepseek-ai/dsh-agent-instructions` 0.2.0-rc.2 still defines `USER_GLOBAL_FILE = "AGENTS.md"` joined onto `dshHome` (`$DSH_HOME` or `~/.dsh`), loaded before the project chain — read out of the shipped `app.asar`, not assumed. The file itself is byte-unchanged (sha256 `6994D906…3A600DF9D`, 5133 B). **Honest limit:** the live-injection proof on record is from 0.1.5-rc.2 (2026-09-16); it was not re-run inside a 0.2.0-rc.2 session, and the canonical note says so.

## 5. Discovery: DSH `settings.yaml` is deprecated by the product

`%USERPROFILE%\.dsh\settings.yaml` — the recorded source of `context/configs/ai/dsh.json` — **no longer exists**, and the collector correctly downgraded the profile to `source_state: stale` with reason `config source confirmed absent during scan`. This is the designed §8 behaviour, not a fault.

The cause is in the shipped bundle: once Cordis configuration settles, a `settings.yaml` left in the harness home by earlier releases is **imported once**, each section written into the Cordis entry of the same id (`ui-developer-tools` → `ui-settings`, `ui-onboarding` → `ui-settings-general`, `shell` → the platform shell executor entry), and the file is renamed to `settings.yaml.imported` **before** the first write. So the disappearance is the product's migration, not a MachineContext action, and it is permanent.

Deliberately **not** done in this round: re-pointing the profile at the Cordis patch layers. That needs a new allowlist, fixture and leak test (§7), the patch files are a different shape (patch lists, not `llm-*` sections) and may carry inline keys, and this round's DSH scope was ownership. It is written up as an explicit follow-up in OPERATIONS §4.3 and in the profile's own `curated.notes`. Note that the **MCP** collector already reads those patch layers, so `mcp.json` is current — including the new `profiles\desktop\cordis.patch.yml` source that appeared with the Desktop install.

## 6. Kimi Code: the brief's premise did not match the machine

The brief described a `kimi` CLI with `~/.kimi-code\config.toml` and version 2.1.1. What is installed is **Kimi Code 1.0.4, an Electron desktop app** (Moonshot AI) at `D:\KimiCode\Kimi Code\Kimi Code.exe`, HKCU uninstall key `8e1a5331-d39b-57b9-8da5-3dc7219b2990`, feed `code.kimi.com/kimi-code/desktop/` → 1.0.4 (so it is current).

Evidence that no CLI exists, gathered before concluding: `where.exe kimi` and `Get-Command kimi -All` return nothing; a recursive search for `kimi.exe|kimi.cmd|kimi.ps1|kimi.bat` across `D:\`, `E:\`, `%USERPROFILE%`, `%LOCALAPPDATA%`, `%APPDATA%` found nothing; the npm-global tree has no Kimi package; and the shipped `app.asar` contains no CLI-install code path (no `installCli` / `kimi.cmd`, no `--print` / headless entry). The desktop app *embeds* the kimi-code agent core, which is why the CLI config semantics still show up in its code.

Config home: `kimiHome()` = `KIMI_CODE_HOME` or `%USERPROFILE%\.kimi-code`. On disk it currently holds only `cache\`, `logs\`, `server\instances\` (empty), `sessions\`, `device_id`, `workspaces.json` (empty). `config.toml`, `tui.toml`, `mcp.json` and `credentials\` (OAuth, mode 0600) **do not exist** — the app is installed but never configured or logged in. Consequently **no config profile was registered**: there is nothing to project, and a profile over absent files would be pure noise. This is recorded as a future §7 candidate once `config.toml` appears.

Rules deployment: the shipped loader `loadAgentsMdForRoots` collects `join(brandHome ?? join(homeDir, ".kimi-code"), "AGENTS.md")` **first**, then `~/.agents/AGENTS.md` / `agents.md`, then per-directory project candidates, deduped by normalized path. `~/.agents/AGENTS.md` does not exist here (only `~/.agents\skills`), so exactly one user-global copy is injected — no global-plus-duplicate. `%USERPROFILE%\.kimi-code\AGENTS.md` was therefore created as a **byte-identical** copy of the shared personal ruleset (`A9829D5C…97BB9229`, 3851 B), the same content already used by `~\.codex\AGENTS.md` and `~\.zcode\AGENTS.md`. No Kimi-specific rules were invented. The bundle also contains a Claude-compatibility *import* flow (`~/.claude/AGENTS.md`, `~/.claude/CLAUDE.md`) but that is a user-invoked import, not an automatic load path, and was not triggered.

**The required live-load probe could not be performed.** The app is not logged in and exposes no headless mode, so there is no non-interactive way to run a turn. The canonical note states this explicitly: the path and additive ordering are runtime-code-level evidence, not a live-load observation, and the probe is owed after the user signs in. This follows the existing precedent in this repo (the Qoder CN rules note distinguishes the same two evidence grades).

Git Bash dependency: `locateWindowsGitBash` probes `KIMI_SHELL_PATH`, then derives `<gitRoot>\bin\bash.exe` and `<gitRoot>\usr\bin\bash.exe` from the `git.exe` found on PATH (`D:\Git\Git\mingw64\bin\git.exe` → `D:\Git\Git\bin\bash.exe`, which exists), then falls back to Program Files and `%LOCALAPPDATA%\Programs\Git`. It does **not** read the `GitForWindows` registry key. Automatic discovery succeeds on this machine, so **no `KIMI_SHELL_PATH` was added** — that would be dead configuration.

## 7. Location, duplicate and PATH discipline

- Every dedicated install root is preserved: `E:\Codex\codex-cli`, `D:\Claude\cli`, `D:\OMP`, `D:\GrokBuild\home`, and now DSH's command coming from `D:\DSH-desktop`. Nothing was "unified" onto npm-global or winget; no new shim was created.
- No duplicate installs found: `E:\Dev\npm-global\node_modules\{@openai,@anthropic-ai,@xai-official,@google}` are **empty leftover scope directories** with no packages, so no shadow copy of any dedicated install exists. Left as-is.
- Grok's known alternative copy `%USERPROFILE%\.grok\bin\grok.exe` (0.2.112) is still present and is still recorded as `alternative_installations` by the collector.
- The only PATH change in this round is the intentional DSH ownership switch (one entry added by the product, one retired entry removed).
- Observed but **not** acted on (out of round scope): Qoder CN is now running from `D:\Qoder-CN\Qoder CN\.qoder-versions\0.4.3\` while canonical records 0.4.2. Noted here so the next round refreshes it with the §8 running-process evidence rather than trusting the registry or the install-root exe.

## 8. Canonical changes

Collector-owned (routine sync, no hand edits): versions for `agy`, `claude-code`, `codex-cli`, `codex-desktop`, `dsh`, `grok`, `omp`; `dsh` executable/command-resolution switch; `codex-desktop` versioned AppX path; `mcp.json` `cua_node` hash, `cua_repl` path and the new DSH desktop patch-layer source; `dsh.json` → `source_state: stale` (+ index); `codex-cli.json` model `gpt-6-sol` → `gpt-6.1-sol` plus effort read as high-to-medium mid-round and edited back to high before publish, so the published profile keeps high (user/Desktop-side edits of config.toml); `omp.json` `webSearchOrder` removed / `modelRoles.web` added / new `retry`,`compaction` unprojected keys; `qoder.json` `mcp-router.json` `exists` flip (runtime-transient, expected per §8); `machine.json` PATH lists and storage free space.

Curated (one-time script `.local\curated-2026-09-30-ai-tooling-round.ps1`): new entities `dsh-desktop` and `kimi-code-desktop`; curated notes on `dsh`, `agy`, `omp`, `grok`, `claude-code`, `codex-cli`; `dsh.json` profile curation; relationship `dsh provided_by dsh-desktop`. `context/conventions.json` `ai_cli_install_roots.dedicated_roots`: `D:\DSH` → `D:\DSH-desktop`. Docs: OPERATIONS §4.2 (OMP backup correction), §4.3 (rewritten for the two-entity/one-command model, the official registration path, and the `settings.yaml` deprecation), §7 step 0 (read the shipped loader instead of guessing), §8 (two more silently-aging entities); `DECISIONS.md` **D040** — one authoritative command per CLI, ownership expressed as a `provided_by` relationship, retire PATH ownership without deleting the old root.

No collector, schema or script logic changed, so the full test suite was not required by §2.3 — it was still run as regression cover because canonical record shapes changed (new entities, new relationship).

## 9. Gates

1. `sync.ps1` — overall health `success`, all 10 providers `success`, validation `ok`, 0 errors / 0 warnings.
2. `git diff` reviewed line by line. This caught **two real defects introduced by the curation script**, both fixed before publish:
   - **Doubled backslashes.** The curation script wrote path literals inside single-quoted PowerShell strings using JSON-style `\\`, so the values carried two real backslashes and `CURRENT.md` rendered `D:\\DSH-desktop\\DeepSeek Harness.exe`. Repaired by collapsing each pair in the two new entities (`.local\fix-doubled-backslash2.ps1`), then confirmed by a decoded-value scan across `ai.json`, `relationships.json`, `conventions.json`, `dsh.json` and `CURRENT.md`: **0 remaining occurrences of two consecutive backslashes**. The existing entities were already correct, because the collector writes them through `ConvertTo-McNormalizedPath`.
   - **Unwrapped single-element sequences.** The same repair pass bound one-element arrays through an untyped parameter and flattened them: `config_paths` on `kimi-code-desktop` became a bare object (caught by `sync`, which rejected the proposal with `contract_type_mismatch` at `$.software[13].observed.config_paths`), and three `evidence[].fields` values became bare strings (caught only by an explicit scan, because the validator tolerated them). Both were restored (`.local\fix-config-paths-array.ps1`, `.local\fix-fields-arrays.ps1`) and a full contract-sequence sweep over every `ai.json` record now reports **all contract sequences OK**.
   - Process lesson: hand-written curated records bypass the normalizers the collectors use, so they must be re-validated through `sync` (which validates the merged proposal, not just the on-disk file), and every multi-valued contract field must be checked for arity-1 collapse.
3. `validate.ps1` — `ok: true`, 0 errors, 0 warnings, 0 findings.
4. `tests/run-tests.ps1` — all blocks pass, re-run after both repairs.
5. Idempotency: repeat syncs changed only `context/status.json`'s `verified_at` heartbeat (verified by hashing all 28 canonical files before and after; the only delta was that heartbeat). The one-time convergence of the new records — entity ordering by `id` and relationship ordering — happened on the first sync after curation, as expected.
6. Privacy sweep over the added diff lines: no key/token/cookie/bearer/authorization/private-key shapes. Two environment variables holding Grok gateway API keys were visible while enumerating user environment variables during the audit; they were never written to canonical, the devlog or any tool output beyond that transient listing, and only the fact that such variables exist is recorded. `D:\GrokBuild\home\config.toml` inline `api_key` values, `~\.dsh\.credentials.yaml`, `~\.omp\agent\agent.db` and `~\.kimi-code\credentials\` were never read — only hashed or checked for existence.


## 10. Still owed by the user

- **Kimi Code**: sign in once, then re-run the rules live-load probe (see section 6). Nothing else about Kimi needs manual work — DSH's command registration did *not* need a GUI step.
- **Grok default model**: the `grok-4.5` entry on `api.aijws.com` returns `GROUP_DELETED` from the gateway. Fixing it is an account-side action with that provider, not a local install problem; `grok -m dasu` works meanwhile.
