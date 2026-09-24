# Devlog — 2026-09-25 routine AI CLI upgrade round (OMP, Agy, Grok, Claude Code, Codex CLI, OpenCodex)

Scope: bring the six AI CLIs named in this round up to their official stable latest in place, verify command resolution and that no config/auth/user data was disturbed, then record the result. **DSH was deliberately not touched** (it stays on 0.1.5-rc.2 pending its own round), and so were Qoder / Qoder CN, Antigravity Desktop and every other AI/desktop tool.

The round also produced one substantive diagnostic result: the reported Gemini-in-OMP failure was **reproduced and localized** (it is the web_search path, not chat, not OAuth and not quota), and one root-cause fix: **`grok update` was permanently broken by a stale config value, and now works**.

## Upgrade results

| Tool | Before → After | Mechanism | Executable (unchanged) |
| --- | --- | --- | --- |
| OMP / Oh My Pi | 18.2.1 → **18.3.0** | `omp update` (stable; `omp update --check` reported 18.3.0) | `D:\OMP\omp.exe` |
| Agy | 1.2.7 → **1.2.10** | already 1.2.10 on the machine before this session — canonical catch-up only, see below | `%LOCALAPPDATA%\agy\bin\agy.exe` |
| Grok Build CLI | 1.0.30 → **1.0.41** | `grok update` (native self-updater, after fixing a config value) | `D:\GrokBuild\home\bin\grok.exe` |
| Claude Code | 2.1.270 → **2.1.281** | `npm install --prefix D:\Claude\cli @anthropic-ai/claude-code@2.1.281` | `D:\Claude\cli\claude.cmd` |
| Codex CLI | 0.154.0 → **0.156.1** | `npm install --prefix E:\Codex\codex-cli @openai/codex@0.156.1` | `E:\Codex\codex-cli\codex.cmd` |
| OpenCodex | 2.42.0 → **2.64.0** | `npm install -g @bitkyc08/opencodex@2.64.0` (existing prefix `E:\Dev\npm-global`) | `E:\Dev\npm-global\opencodex.cmd` |

Stable-channel checks made at execution time, so the target numbers were not assumed:

- **OMP** — GitHub `can1357/oh-my-pi` latest non-prerelease release is `v18.3.0` (published 2026-09-24).
- **Agy** — GitHub `google-antigravity/antigravity-cli` latest non-prerelease release is `1.2.10` (published 2026-09-24). The bundled `agy changelog` still tops out at 1.2.7, i.e. the embedded changelog lags the binary — do not use it as the version authority.
- **Grok** — `x.ai/cli/stable` returned `1.0.41`; `x.ai/cli/alpha` returned the *same* `1.0.41`, so 1.0.41 is stable latest. This is one patch **above** the 1.0.40 the round expected.
- **Claude Code** — npm dist-tags are `latest: 2.1.281`, `stable: 2.1.273`, `next: 2.1.282`. The existing install was created from the default dist-tag (`^2.1.270`), so `latest` = 2.1.281 is the consistent choice and matches the round's expected target. **Caveat for future rounds:** Anthropic publishes a `stable` tag that is currently *older* than `latest`; "stable latest" therefore needs to be disambiguated rather than assumed, and `next` is ahead of both.
- **Codex CLI** — npm `latest: 0.156.1`; `alpha: 0.158.0-alpha.8` was deliberately not used. Confirmed after install: `codex-cli 0.156.1` (stable, not alpha).
- **OpenCodex** — npm `latest: 2.64.0`, `preview: 2.64.0-preview.20260923`. Only `latest` was installed, even though the preview shares the same base version number.

## Grok: the `grok update` failure was a stale config value, not a broken layout

This retires a workaround that two earlier rounds had recorded as permanent.

`D:\GrokBuild\home\config.toml` (the grok home, `GROK_HOME=D:\GrokBuild\home`) carried:

```toml
[cli]
installer = "npm"
```

The updater honours that value and takes the npm install path, which fails here. Verified by A/B on the same binary:

| `installer` value | `grok update --check` |
| --- | --- |
| `"npm"` (as found) | `Update check failed: program not found` (exit 1) |
| anything else | `A new version of Grok Build is available: 1.0.30 -> 1.0.41 [stable]` |

The value the official installer (`x.ai/cli/install.sh`) persists for native installs is `installer = "internal"`, which is what this layout actually is (native `grok.exe`/`agent.exe` under `%GROK_HOME%\bin`), so that is what was written — a one-line provenance correction, not a preference change. `grok update` then installed 1.0.41 in place.

- **Verified:** the A/B behaviour, the value the official installer writes (read from the installer script itself), and the successful in-place update.
- **Inference, not verified:** *why* the npm path fails. The likely cause is that the updater spawns `npm`, which on Windows resolves to `npm.cmd` and is not found by a bare process spawn. The npm-reinstall hint remains wrong for this layout either way.
- The earlier `install.ps1` + `GROK_BIN_DIR=D:\GrokBuild\home\bin` workaround is retired; `grok inspect`/`grok models`/`grok -p` all work on the self-updated binary.

**The updater rewrote `config.toml` as a TOML round-trip, and that rewrite was checked rather than trusted.** The diff looks alarming (digit separators `500_000` → `500000`, arrays re-wrapped, trailing commas added inside arrays) but is formatting-only. Confirmed two ways: masking the `installer` value and normalizing whitespace, digit separators and trailing commas makes the two versions byte-identical; and an independent TOML parse of the result yields the same content — 17 `[model.*]` tables, 5 `[mcp_servers.*]` tables, 16 inline `api_key` values, 7 skill paths and `models.default = "grok-4.5"` all preserved. The only semantic delta in the file is the intended `installer` line. The trailing commas are legal TOML 1.0.

## OMP Gemini / Antigravity diagnostic — reproduced, and it is neither OAuth nor quota

No re-authentication was performed: no logout, no `agent.db` deletion, no OAuth clear, no `projectId` change. The existing credential was used as-is.

### Chat works

```
omp -p --model google-antigravity/gemini-3.8-flash "Reply exactly: OK"   ->  OK   (exit 0)
```

The OMP log for that run shows `provider=google-antigravity`, `model=gemini-3.8-flash`, `stopReason=stop`, `contentBlocks=1`, `contextWindow=1048576`, and `provider proxy resolved provider=google-antigravity source=none`. **No 429, no 401, no 400, no 404, no retry, no token refresh.** Ordinary chat on the default model is healthy on 18.3.0.

### The failure is the Gemini web_search path, and it has a sharp version cutoff

`omp search` with an explicit Antigravity model reproduces it exactly:

| Logical model | Chat | web_search (`omp search`) |
| --- | --- | --- |
| `gemini-2.5-flash` | — | OK |
| `gemini-3-flash` | — | OK |
| `gemini-3.5-flash` | — | OK |
| `gemini-3.6-flash` | OK | **404 NOT_FOUND** |
| `gemini-3.7-flash` | OK | **404 NOT_FOUND** |
| `gemini-3.8-flash` | OK | **404 NOT_FOUND** |

The exact safe error, and nothing else, is:

```
Error: Gemini Cloud Code API error (404):
{ "error": { "code": 404, "message": "Requested entity was not found.", "status": "NOT_FOUND" } }
```

Exit code 1. No credential material is involved or emitted.

This is a clean characterization of the known upstream issue: the Gemini **web_search** provider routes through the **Cloud Code API** (not the chat path), and for logical model ids 3.6 and above it fails to resolve to a valid wire model id, returning `404 NOT_FOUND`. Chat routes the same models fine, which rules out the model not existing and rules out account entitlement. This lands squarely in bucket **B — a known OMP/Antigravity routing/model-mapping bug** — and it is reproducible on 18.3.0.

- **Operational impact is currently limited.** `providers.webSearchOrder` starts with `parallel`, then `perplexity`, then `gemini`, so a plain `omp search` never reaches the broken provider: it returned results via **Parallel** and exited 0. The bug only bites when the Gemini provider is selected explicitly (as above) or when the earlier providers in the order fail.
- **Not tested:** whether the underlying Cloud Code wire model id can be confirmed from logs. The 404 is raised before any model resolution is logged, so no wire id was observable — reporting one would be a guess.

### Why this is not an account-quota problem

`omp usage` shows the Antigravity credential is logged in with **two accounts** and essentially untouched quota — Gemini (Weekly) 0.0% and 4.1% used, Gemini (5 Hour) 14.1% on one account and not reported on the other; capacity readout `5h → 0.14/1 account used (0.86× quota left)`, `7d → 0.04/2 accounts used (1.96× quota left)`. The same command reads the Codex credential (1 account, 5h 51%, 7d 87%).

So, per the round's classification: **A (real account quota exhaustion) is ruled out by measurement**; the 404 is a routing/model-mapping defect, i.e. **B**. **C (undetermined) does not apply** to the web_search 404, which is deterministic and reproduced three times. No evidence pointed at OAuth at any stage, so no re-authorization was attempted.

## Per-tool smoke evidence

| Tool | Probe | Result |
| --- | --- | --- |
| OMP | `omp -p --model google-antigravity/gemini-3.8-flash "Reply exactly: OK"` | `OK`, exit 0 |
| Agy | `agy -p "<question only answerable from the user-global rules>"` from a scratch git repo with no `AGENTS.md`/`GEMINI.md` | `E:\MachineContext\CURRENT.md`, exit 0 |
| Grok | `grok -p "Reply exactly: OK"` | `OK`, exit 0 |
| Claude Code | `claude -p "Reply exactly: OK"` | `OK`, exit 0 |
| Codex CLI | `codex exec --skip-git-repo-check "Reply exactly: OK"` | `OK`, exit 0 |
| OpenCodex | `opencodex status` + `opencodex doctor` | all path/temp/routing checks `ok`, exit 0 |

The Agy probe is the strongest of these: `E:\MachineContext\CURRENT.md` appears **only** in `%USERPROFILE%\.gemini\config\GEMINI.md`, and the scratch repo contains no project rules, so the answer can only come from the user-global ruleset actually reaching the model. This re-verifies the 1.2.7 result on 1.2.10.

Grok's Claude-compatibility path is also intact: `grok inspect` still reports the global personal ruleset loading from `%USERPROFILE%\.claude\CLAUDE.md`, with 52 user-scope skills resolving.

Two harmless operational notes recorded rather than "fixed": `claude -p` prints an informational `[claude-code:unrecognized_model]` notice about the configured `deepseek-v4-pro[1m]` alias while still returning correct output and exit 0; and `codex exec` warns that the pre-existing `disable_response_storage` key in `%USERPROFILE%\.codex\config.toml` is no longer recognized. Neither was changed — this round does not edit user configuration.

## Agy was a canonical catch-up, not an upgrade

The round's baseline said 1.2.7, but the machine was **already on 1.2.10** when this session started: `E:\AGY\cli\agy.exe` has mtime 2026-09-24T17:30:28+08:00, i.e. the upgrade happened the day before, outside this session. `agy update` on 2026-09-25 printed `Checking for updates... (current version 1.2.10)` / `You are already on the latest version.` and exited 0. Canonical was simply behind, so this round refreshed the record instead of performing an upgrade — the devlog says so explicitly so the version jump is not misread as work done here.

One resolution detail worth keeping: `%LOCALAPPDATA%\agy\bin` is a **directory junction** to `E:\AGY\cli`. `where.exe`/`Get-Command` therefore legitimately report the `%LOCALAPPDATA%` path while the real file lives on `E:`. The recorded executable is correct as-is.

## Location, duplicate and PATH discipline

All six dedicated roots are unchanged and each command resolves to exactly one location:

```
omp        D:\OMP\omp.exe
agy        %LOCALAPPDATA%\agy\bin\agy.exe
grok       D:\GrokBuild\home\bin\grok.exe
claude     D:\Claude\cli\claude.cmd
codex      E:\Codex\codex-cli\codex.cmd
opencodex  E:\Dev\npm-global\opencodex.cmd
```

- No install method was "unified" for convenience: no winget, no new directories, no PATH shims, no duplicate npm-global copies. The user PATH was re-read in full afterwards and is unchanged — no installer appended anything.
- OpenCodex stayed on the plain npm-global prefix it already used, rather than being migrated to a dedicated root.
- `D:\OMP\omp.exe.1790270148771.31792.0.bak` is the OMP updater's own backup of the previous binary. Updater-managed, left in place — older backups are not proactively cleaned.
- OpenCodex's global install reported `changed 100 packages` because npm reified the whole global tree; the unrelated globals were therefore re-checked and all still resolve (opencli 1.8.4, lark-cli 1.0.64, mcporter 0.9.0, agently-cli 1.0.5, agent-browser 0.27.0, codex-threadripper 0.3.4). No `@anthropic-ai`/`@openai`/`@xai-official` package exists in the npm-global tree, so no shadow copies of the dedicated installs were introduced.
- OpenCodex remains inactive exactly as before (proxy not running, `routing=native`, `service=absent`, `shim=absent`). The abandoned Astra experimental context management was **not** revived or re-tested — this was a routine CLI upgrade. `opencodex doctor` does independently corroborate the Codex upgrade, resolving the runtime at `E:\Codex\codex-cli\codex.cmd` (0.156.1).

## User data preservation

Byte-compared before and after (sha256), all unchanged: `%USERPROFILE%\.omp\agent\config.yml`, `models.yml`, `.env`, `history.db`; `%USERPROFILE%\.gemini\antigravity-cli\settings.json`; `%USERPROFILE%\.gemini\config\GEMINI.md`; `%USERPROFILE%\.claude\CLAUDE.md`; `%USERPROFILE%\.codex\config.toml`; `%USERPROFILE%\.codex\AGENTS.md`. `%USERPROFILE%\.claude\skills`, `%USERPROFILE%\.gemini\config\plugins` and `%USERPROFILE%\.codex\plugins` (+ `plugins\cache`, `sessions`) still exist; nothing was cleaned.

Files that did change, each for a known reason: `.claude.json` and `.omp\agent\agent.db` (runtime state written by the smokes), the two npm `package.json` files (dependency specs bumped by the installs), and `D:\GrokBuild\home\config.toml` (the `installer` line plus the updater's formatting round-trip analysed above). `config.yml`, which carries the OMP default model, is byte-identical — `modelRoles.default` is still `google-antigravity/gemini-3.8-flash` and the TokenRhythm provider is intact.

**DSH was not upgraded and not modified:** `dsh --version` is still `0.1.5-rc.2`, `D:\DSH\package.json`/`package-lock.json` are untouched (mtime 2026-09-15), `%USERPROFILE%\.dsh\settings.yaml` (2026-09-19) and `.credentials.yaml` (2026-09-16) are untouched, no `dsh` package exists in the npm-global tree, and no DSH plugin/quarantine/provider/preset was read or written.

## Routine drift observed in the same sync (not from this round)

Recorded so a reviewer does not attribute these to the upgrades:

- `codex-desktop` auto-updated 26.915.4065.0 → 26.917.9434.0 (MSIX), which also moved the `cua_node` runtime directory hash and the `cua_repl` MCP command path in `context/configs/mcp.json`.
- `winget` auto-updated 1.29.290 → 1.29.380.
- `context/configs/ai/codex-cli.json` now projects `model: gpt-6-sol` (was `gpt-6-astra`) — a user-side `config.toml` change made between the last publish and this one; the file's hash was already `gpt-6-sol` at this round's start, so it is drift, not an upgrade effect.
- `machine.json`: D: free space 7.2 → 57.8 GiB and E: 102.0 → 110.0 GiB, and PATH entry count 41 → 44 from three `E:\CS2MOD\...\.cache\dotnet-home\.dotnet\tools` entries. All three were already present at this round's start (captured in the pre-upgrade PATH snapshot), so no installer touched PATH.

## Gates

1. `sync.ps1` — overall health `success`, all 10 providers `success`, validation `ok`, 0 findings. No collector, script or schema change was needed: the existing providers recognised every new version, so per the round's gate the full test suite was not run.
2. Diff reviewed line by line. Beyond the six version bumps, the only canonical edits are four curated notes (grok root cause + 1.0.41, agy catch-up, omp 18.3.0, opencodex 2.64.0) applied by a one-time script `.local/curated-2026-09-25-ai-cli-upgrades.ps1`. The grok note was a **correctness fix**: it previously asserted that `grok update` is permanently broken in this layout and prescribed a manual artifact copy, which this round falsified.
3. `validate.ps1` — `ok: true`, 0 errors, 0 warnings, 0 findings.
4. Idempotency: a repeat sync reproduced no canonical change at all (`context/software/ai.json` byte-identical), and a further sync across all 29 canonical files changed only `context/status.json`'s `verified_at` heartbeat and its `CURRENT.md` projection.
5. Privacy sweep over the added diff lines for key/JWT/bearer/authorization/token/cookie/private-key shapes: **0 hits**. The only credential-adjacent strings are the words `api_key` and `credentials` inside prose notes; no value, token, cookie or header appears anywhere in the diff. OAuth state was only ever observed as presence/usage metadata, never read.

## Not done in this round (by instruction)

DSH (0.1.7-rc.2 stays for a separate round); Qoder / Qoder CN; Antigravity Desktop; any other AI or desktop tool. The OMP Gemini diagnostic was deliberately kept out of the canonical schema as a one-off diagnosis and recorded here instead; only the durable Grok updater root cause was promoted into curated notes.
