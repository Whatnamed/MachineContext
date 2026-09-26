# Devlog — 2026-09-26 DSH Parallel Search MCP over the existing MCP client

Scope: attach the official Parallel Search MCP (`https://search.parallel.ai/mcp`) to the live DSH `web` profile as a configuration-only change, verify it end to end, make MachineContext actually collect DSH profile MCP declarations, and route web access to it.

DSH was **not** upgraded and stays `0.1.5-rc.2`. Desktop was not installed. No model, provider, plugin or OMP configuration was changed, no package was installed, and no historical profile/plugin state was cleaned up. The only credential work was adding a newly created Parallel key to the Harness-home `.env`; its value is not recorded anywhere.

## Confirmed machine state before the change

Read from the running machine, not from the previous repository snapshot:

| Fact | Evidence |
| --- | --- |
| DSH version `0.1.5-rc.2` | `D:\DSH\node_modules\@deepseek-ai\dsh\package.json` |
| active profile `web` | live process command line `"node" "D:\DSH\node_modules\@deepseek-ai\dsh\lib\bin.js" web --port 3080` |
| `DSH_HOME` = `C:\Users\hasee\.dsh` | process environment |
| no MCP row existed | `dsh --profile web --dump-config` → 174 top-level entries, none naming `dsh-mcp-client`; `%USERPROFILE%\.dsh\cordis.patch.yml` is `[]` |
| `@deepseek-ai/dsh-mcp-client` is already present | `D:\DSH\node_modules\@deepseek-ai\dsh-mcp-client`, version `0.1.5-rc.2` |

Because the client ships with the harness, the whole integration is configuration-only — nothing was installed and no third-party plugin bundle was introduced.

## How the row was added

`%USERPROFILE%\.dsh\profiles\web\cordis.patch.yml` is a top-level YAML array of loader patch entries. The syntax that appends a new plugin row is an entry carrying `insert` **without** an `id`: `applyEntryPatches` in `@deepseek-ai/dsh-app-boot` pushes such a list onto the top-level entry list, while an `insert` with an `id` targets a group's children. That is what was used, so no existing patch row was touched:

```yaml
- insert:
    - id: mcp-parallel
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: parallel
        transport: streamable-http
        url: https://search.parallel.ai/mcp
        headers: !!js 'process.env.PARALLEL_API_KEY ? { Authorization: `Bearer ${process.env.PARALLEL_API_KEY}` } : undefined'
```

The row was first inserted without the `headers` line and the header was added later, once the credential existed (see the credential section below for why the ternary is written the way it is).

One backup was taken before the first edit (`cordis.patch.yml.bak-20260926-mcp-parallel`). The insert itself was a pure addition — `dsh --profile web --dump-config` showed exactly six added lines and nothing else, 174 → 175 entries, 2216 → 3231 bytes. The file now stands at 3813 bytes after the header and comment updates.

**The insert itself needed no restart.** The `web` profile template carries `patchReload: "live"`, and `runProfile` registers the profile patch file with Cordis HMR, so the edit hot-swapped the plugin in place. Corroboration: the host process (PID 13480, started 11:02:06) never changed across the edit, while the profile root `cordis.yml` was rewritten at 16:03:04 — one second after the 16:02:59 edit — which is the reload path's own behaviour. A restart *was* required later, but for a different reason: `%USERPROFILE%\.dsh\.env` is read once at launch, so the credential could not reach the already-running process.

## Credential handling: no reusable key existed, then a new one was configured

The round asked to reuse an existing local Parallel credential if one could be referenced safely. **It could not, because none existed in any form DSH can reach:**

| Location checked | Result |
| --- | --- |
| current process environment | absent |
| Windows **User** environment (registry) | absent |
| Windows **Machine** environment (registry) | absent |
| `%USERPROFILE%\.dsh\.credentials.yaml` refs | only `OPENAI_API_KEY`, `TOKENRHYTHM_API_KEY`, `DEEPSEEK_API_KEY` |
| Windows Credential Manager (`cmdkey /list`, target names only) | no Parallel target |
| OMP `%USERPROFILE%\.omp\agent\.env` | only `TOKENRHYTHM_API_KEY` |
| OMP `agent.db` / `models.db` / `history.db`, searched for the **name** `PARALLEL_API_KEY` only | no occurrence |

**Conflict with the stated premise, recorded as required.** The task described OMP as already configured with, and having used, a Parallel API credential. The machine shows only `providers.webSearchOrder: [parallel, perplexity, …]` in `%USERPROFILE%\.omp\agent\config.yml` — a *preference ordering*, which is not evidence that a key was ever stored. No Parallel key was found anywhere. Nothing was changed to "fix" that; OMP was left untouched.

### Where the credential lives, and why that file

A new key was created by the user and placed in `%USERPROFILE%\.dsh\.env`. That is the only one of three candidate channels that reaches an MCP header:

| Channel | Works? | Exposure |
| --- | --- | --- |
| `%USERPROFILE%\.dsh\.env` | **yes** | only the DSH process reads it |
| Windows User environment variable (`setx`) | yes | every process under the account, permanently |
| `.credentials.yaml` refs | **no** | smallest, but unreachable from an MCP header |

`loadLayeredEnv` in `@deepseek-ai/dsh-app-boot` calls `process.loadEnvFile` on the Harness-home `.env` and materializes each value into `process.env` (`if (process.env[name] === void 0) process.env[name] = value`). The MCP client's header is produced by a `!!js` expression that the Cordis loader evaluates **synchronously** (`interpolate` → `with (ctx) { eval(expr) }`, no await anywhere in the chain), while `ctx.credentials.resolve()` is asynchronous — so a `.credentials.yaml` reference can feed an LLM adapter's `apiKeyEnv` (which is how TokenRhythm works: `TOKENRHYTHM_API_KEY` is absent from process, User and Machine scopes) but can never feed an MCP header.

The `.env` file was loaded at the 16:41:30 restart, which is what made the connection authenticated. The credential is recorded here as **source + state only**; the value never entered the repository, a log, or a terminal, and the probe scripts that read it printed status codes and lengths only.

**The key does not leak to child processes.** `dsh-subprocess`'s `scrubbedParentEnv` drops ambient names matching `/KEY|PASSWORD|SECRET|TOKEN/i` before every harness spawn, and `PARALLEL_API_KEY` matches. This is now a positive result rather than an ambiguous one: authentication proves the key is present in the host environment, and the harness's own shell tool still cannot see it.

### Auth mode is authenticated

Confirmed by a behavioural discriminator rather than by trusting the config text. The Parallel `session_id` argument is documented as "ignored on paid-tier keys", and that is observable:

| Probe | `session_id` returned |
| --- | --- |
| anonymous connection, client passes a known id | echoed back verbatim |
| authenticated connection, same known id | server-generated `session_<hex>` |

The live DSH connection returned `session_8ed71879…` for a client-supplied `deadbeef…`, so it is authenticated. Two independent calibrations ran against the endpoint first (anonymous echoes, authenticated ignores) to prove the discriminator before it was used.

## Verification

- **Connection and tool discovery.** The endpoint reports `serverInfo.name = "Parallel Web Search MCP Server"`, version `1.27.0`, and advertises exactly two tools, `web_search` and `web_fetch`. DSH exposes them as `mcp__parallel__web_search` and `mcp__parallel__web_fetch`, and both are registered on the live session.
- **Search smoke test.** `mcp__parallel__web_search` (objective "DeepSeek Harness latest release", three queries) returned `search_id` `search_82b57b065f926d7685dc08b9bfba297c` with nine results carrying URL, title, publish date and excerpts. This is the MCP path, not the harness's built-in DeepSeek search.
- **Fetch smoke test.** `mcp__parallel__web_fetch` on `https://github.com/deepseek-ai/deepseek-harness` returned `extract_id` `extract_e92045a7da6eb46fe7efc45d763eda17` with usable README markdown (project description, run instructions, licence, top-level file list) — not a bare link.
- **No fallback, no interference.** The harness's native `web_search` and `web_fetch` are still registered and were exercised separately during the same session; the MCP tools are additional, namespaced tools.
- **Regression.** DSH version still `0.1.5-rc.2`; `%USERPROFILE%\.dsh\settings.yaml` byte-identical (sha256 `4034CE6B…`, mtime 2026-09-19) so the default model stays `tokenrhythm` / `deepseek-flash`; TokenRhythm provider unchanged; shell tooling used throughout; the composed entry list keeps all 43 `disabled: true` quarantine rows and contains exactly one `dsh-mcp-client` row.

## MachineContext: the MCP inventory now covers DSH

The MCP inventory hard-coded `dsh: no file-based MCP configuration discovered`, which this change made false. That is a small, natural, additive gap in the collector's own existing coverage claim, so it was closed rather than documented around — `context/configs/mcp.json` was **not** hand-edited.

`Get-McMcpInventoryRecord` now reads DSH's Cordis patch layers — the home-level `%USERPROFILE%\.dsh\cordis.patch.yml` plus every `%USERPROFILE%\.dsh\profiles\<name>\cordis.patch.yml` — and projects each `insert` row naming `@deepseek-ai/dsh-mcp-client`, using the profile directory name as the server scope and DSH's `transport` property instead of the Claude/Gemini-style `type`. Privacy follows the existing Agy rule: `headers` (which may carry an `Authorization` bearer) and env **values** are never read, only env names. A missing patch layer keeps the old unresolved entry; an existing one is authoritative even when it declares no servers.

Two defects surfaced in the same function and were fixed in a separate commit:

- **Phantom `unsafe-argument` redactions.** A source with no `args` key resolves to a null, and PowerShell 7.6 wraps that into a one-element array holding null, so `$args.Count -gt 0` held and the sequence-aware filter reported an argument that does not exist. The published inventory had been carrying three such false redactions (`claude-code` figma, `codex-cli` cua_repl, `qoder` GitHub — all three are url-only servers, verified in the real config files). Nulls are now dropped before the filter.
- **`[]` was a parse failure.** The YAML subset reader threw on a document that is exactly `[]`. That is a complete YAML document meaning "no entries" and it is precisely what DSH's profile template writes into a fresh `cordis.patch.yml`, so the reader now returns an empty list.

Both are covered by the new fixture `tests/fixtures/config-profiles/mcp/dsh/` (a home-level `[]` layer and a profile layer with a remote server, a stdio server, a non-MCP-client decoy row and a `headers` block) and by the new test *"DSH patch-layer MCP servers are projected per profile without headers"*.

## Tool routing, and what actually forces Parallel to be used

DSH 0.1.5-rc.2 has **no "default search tool"**. Two independent tool families are registered side by side — the harness's native `web_search` / `web_fetch` (backed by the `deepseek-official` and `http` providers) and `mcp__parallel__web_search` / `mcp__parallel__web_fetch` — and the model picks per call. `dsh-web` does have a deterministic provider-selection policy (`searchProvider` / `fetchProvider`, configured in the `web` entry), but that policy only chooses **among registered `dsh-web` providers**, and the MCP client registers *tools*, not a `dsh-web` provider. Parallel therefore cannot enter that pool without a purpose-written provider plugin, which is out of scope here.

The lever used instead is instruction-level: a `## 联网检索` section was added to `%USERPROFILE%\.dsh\AGENTS.md`, which the harness injects into every session's system prompt. It makes the Parallel tools the default, requires a stated reason when falling back to the native ones, and forbids substituting a shell call to the endpoint for a missing tool. This is a preference, not enforcement — it is recorded as such rather than as a guarantee.

## Operational notes learned the hard way

- **A failed initial connection is permanent for the session.** The MCP client's Streamable HTTP transport does not respawn after a failed *initial* connection: the harness still starts, but the server's tools never register, and only a config reload or a restart retries. "The endpoint answers" and "the tools exist" are therefore two different facts and must be checked separately.
- **Comment-only edits do not reload the entry.** The loader compares the resolved config; comments are not part of it. Forcing a reload requires a real config delta.
- **`Object.assign` with an undefined target throws.** A first attempt at the header used `Object.assign(cond ? {…} : undefined, {…})`, which raises `TypeError: Cannot convert undefined or null to object` — only *sources* may be null/undefined. With no key present that would have failed the whole entry activation instead of degrading to anonymous. The shipped form is a spread, which is safe: `({ ...(cond ? {…} : {}), … })`. The wrapping parentheses are mandatory, or the leading `{` parses as a block.

## Canonical changes from this round

- `context/configs/mcp.json` — new `dsh` server `parallel` (scope `web`, transport `streamable-http`, url `https://search.parallel.ai/mcp`); the stale `dsh` unresolved entry removed; both DSH patch layers recorded as `mcp-config` source files; `redactions` now empty after the false ones were corrected. Produced by the routine collector.
- `context/software/ai.json` — routine drift only: **agy 1.2.10 → 1.2.11** (`agy --version` reports 1.2.11; `%LOCALAPPDATA%\agy\bin\agy.exe` mtime 2026-09-26 15:25). This upgrade happened outside this session and was not performed here.
- `context/machine.json` — routine disk free-space drift only (`D:\` −0.25 GiB).
- `context/status.json` / `CURRENT.md` — heartbeat, plus the rendered MCP line now reading `dsh (1)`.
- `context/configs/ai/dsh.json` — unchanged, and correctly so: it projects `settings.yaml`, which was not modified, and DSH's MCP declarations belong to the MCP inventory rather than to that profile.

## Functional verification across site types

Both MCP tools were exercised against a deliberately varied target set rather than one happy path.

`web_fetch`, twelve targets, all through the MCP tool:

| Target | Result |
| --- | --- |
| GitHub repository page (JS-heavy) | ok, real README body |
| `raw.githubusercontent.com` raw file | ok |
| official documentation site | ok |
| `react.dev/learn` (JS-heavy docs) | ok |
| Chinese-language blog (`ruanyifeng.com`) | ok, Chinese body intact |
| arXiv abstract page | ok |
| **arXiv PDF** | ok — server-side PDF parsing returned the abstract, section headings, training hyperparameters and the BLEU result |
| Reddit `r/LocalLLaMA` | ok — real community content, despite Reddit's usual scraper defences |
| Hacker News | ok |
| non-existent path on a live host | typed `http_error`, `http_status_code: 404` |
| non-existent domain | typed `connect_error`, `http_status_code: null` |
| X (`x.com`) | **soft block** |
| LinkedIn | **soft block** |

Batch behaviour: four URLs in one call (the API accepts up to 20), and partial failure is handled correctly — reachable URLs land in `results`, the rest in `errors`, and a failure is never reported as a success. `web_search` was run with multiple queries per call, with Chinese queries, and with recency-sensitive queries; each returned ten results carrying URL, title, publish date and excerpts, mixed across English and Chinese sources.

### The finding that matters: soft blocks are silent

A **hard block** — 403/429/404, or a refused connection — surfaces correctly as a typed entry in `errors`. A **soft block** does not. A login wall, an anti-bot interstitial, a JavaScript-only shell, or a User-Agent-specific SEO fallback returns **HTTP 200, with no error and no warning**, and lands in `results` looking exactly like a success. Two observed cases:

- `https://x.com/` returned `title: "X. It's what's happening / X"` and a body of `See what's happening / Scan to get the app` — the logged-out shell, not the site.
- `https://www.linkedin.com/` returned `title: "linkedin.com"` and a fragment of unrelated NAICS industry codes — a fallback page, not the home page.

Site type does not predict it: Reddit, which normally defends against scrapers, returned real content in the same session. A caller must therefore judge the **content**, not the status — an implausibly short body, a bare call to action, a title degraded to the bare domain, or content that does not answer the objective all mean *not fetched*, and the fallback is `web_search` excerpts or another source. The `AGENTS.md` routing rule now carries this instruction so the judgement does not depend on an agent remembering it.

## Gates

`tests/run-tests.ps1` → all tests pass, including the new DSH MCP test. `sync.ps1` → overall health `success`, all 10 providers `success`, validation `ok`, 0 warnings. `validate.ps1` → `{ok: true, errors: [], warnings: [], findings: []}`. A second sync was idempotent: of 29 canonical files only `context/status.json` and the `CURRENT.md` it renders changed, both heartbeat-only.

## Known limitations left in place

- **Tool routing is a prompt-level preference.** Nothing in 0.1.5-rc.2 enforces that the model calls the Parallel tools; the `AGENTS.md` rule biases it and requires a visible reason on fallback.
- **Soft blocks are indistinguishable from successes at the protocol level.** See above — this is a property of the extracting backend, not of this configuration, and the only defence is content-level judgement.
- **Login-gated, paywalled, interaction-only and geo-restricted pages were not tested** and are expected to be out of reach: Parallel's extract performs a real fetch and parse, not an authenticated interactive browsing session.
- **The credential is a machine-local environment value.** `%USERPROFILE%\.dsh\.env` is not tracked by any collector and its contents are never read for inventory purposes; the repository records only that the MCP is authenticated and where the reference comes from.
- **`headers` is deliberately outside the MCP inventory.** The DSH collector projects serverName/transport/url/command/args/env names only, so the credential-bearing header cannot reach canonical context even by accident.
