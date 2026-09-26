# Devlog — 2026-09-26 DSH Parallel Search MCP over the existing MCP client

Scope: attach the official Parallel Search MCP (`https://search.parallel.ai/mcp`) to the live DSH `web` profile as a configuration-only change, verify it end to end, then make MachineContext actually collect DSH profile MCP declarations.

DSH was **not** upgraded and stays `0.1.5-rc.2`. Desktop was not installed. No model, provider, plugin or OMP configuration was changed, no package was installed, and no historical profile/plugin state was cleaned up.

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
```

One backup was taken first (`cordis.patch.yml.bak-20260926-mcp-parallel`). The file went from 2216 to 3231 bytes; `dsh --profile web --dump-config` then showed exactly six added lines — the new row — and nothing else, 174 → 175 entries.

**No restart was needed.** The `web` profile template carries `patchReload: "live"`, and `runProfile` registers the profile patch file with Cordis HMR, so the edit hot-swapped the plugin in place. Corroboration: the host process (PID 13480, started 11:02:06) never changed, while the profile root `cordis.yml` was rewritten at 16:03:04 — one second after the 16:02:59 edit — which is the reload path's own behaviour.

## Credential handling: anonymous mode, and a premise that the machine does not support

The round asked to reuse an existing local Parallel credential if one could be referenced safely. **It cannot, because none exists in any form DSH can reach:**

| Location checked | Result |
| --- | --- |
| current process environment | absent |
| Windows **User** environment (registry) | absent |
| Windows **Machine** environment (registry) | absent |
| `%USERPROFILE%\.dsh\.credentials.yaml` refs | only `OPENAI_API_KEY`, `TOKENRHYTHM_API_KEY`, `DEEPSEEK_API_KEY` |
| Windows Credential Manager (`cmdkey /list`, target names only) | no Parallel target |
| OMP `%USERPROFILE%\.omp\agent\.env` | only `TOKENRHYTHM_API_KEY` |
| OMP `agent.db` / `models.db` / `history.db`, searched for the **name** `PARALLEL_API_KEY` only | no occurrence |

So the Parallel MCP was configured **without any `Authorization` header**, exactly as the round's fallback instructs. No credential was parsed, dumped or copied, and no OMP state database content was read.

**Conflict with the stated premise, recorded as required.** The task described OMP as already configured with, and having used, a Parallel API credential. The machine shows only `providers.webSearchOrder: [parallel, perplexity, …]` in `%USERPROFILE%\.omp\agent\config.yml` — a *preference ordering*, which is not evidence that a key was ever stored. No Parallel key was found anywhere. Nothing was changed to "fix" that; OMP was left untouched.

Auth mode is therefore anonymous, and that was confirmed by construction plus a control probe rather than by trusting the config text: with no header the endpoint answers `initialize` / `tools/list` / `tools/call` with HTTP 200, while the same `initialize` carrying a deliberately bogus `Bearer` returns **401**. The server validates bearer tokens, so a request that succeeds without one is genuinely anonymous.

## Verification

- **Connection and tool discovery.** The endpoint reports `serverInfo.name = "Parallel Web Search MCP Server"`, version `1.27.0`, and advertises exactly two tools, `web_search` and `web_fetch`. DSH exposes them as `mcp__parallel__web_search` and `mcp__parallel__web_fetch`, and both are registered on the live session.
- **Search smoke test.** `mcp__parallel__web_search` (objective "DeepSeek Harness latest release", three queries) returned `search_id` `search_82b57b065f926d7685dc08b9bfba297c` with nine results carrying URL, title, publish date and excerpts. This is the MCP path, not the harness's built-in DeepSeek search.
- **Fetch smoke test.** `mcp__parallel__web_fetch` on `https://github.com/deepseek-ai/deepseek-harness` returned `extract_id` `extract_e92045a7da6eb46fe7efc45d763eda17` with usable README markdown (project description, run instructions, licence, top-level file list) — not a bare link.
- **No fallback, no interference.** The harness's native `web_search` and `web_fetch` are still registered and were exercised separately during the same session; the MCP tools are additional, namespaced tools.
- **Regression.** DSH version still `0.1.5-rc.2`; `%USERPROFILE%\.dsh\settings.yaml` byte-identical (sha256 `4034CE6B…`, mtime 2026-09-19) so the default model stays `tokenrhythm` / `deepseek-flash`; TokenRhythm provider unchanged; shell tooling used throughout; the composed entry list keeps all 43 `disabled: true` quarantine rows and contains exactly one `dsh-mcp-client` row; the host process never restarted.

## MachineContext: the MCP inventory now covers DSH

The MCP inventory hard-coded `dsh: no file-based MCP configuration discovered`, which this change made false. That is a small, natural, additive gap in the collector's own existing coverage claim, so it was closed rather than documented around — `context/configs/mcp.json` was **not** hand-edited.

`Get-McMcpInventoryRecord` now reads DSH's Cordis patch layers — the home-level `%USERPROFILE%\.dsh\cordis.patch.yml` plus every `%USERPROFILE%\.dsh\profiles\<name>\cordis.patch.yml` — and projects each `insert` row naming `@deepseek-ai/dsh-mcp-client`, using the profile directory name as the server scope and DSH's `transport` property instead of the Claude/Gemini-style `type`. Privacy follows the existing Agy rule: `headers` (which may carry an `Authorization` bearer) and env **values** are never read, only env names. A missing patch layer keeps the old unresolved entry; an existing one is authoritative even when it declares no servers.

Two defects surfaced in the same function and were fixed in a separate commit:

- **Phantom `unsafe-argument` redactions.** A source with no `args` key resolves to a null, and PowerShell 7.6 wraps that into a one-element array holding null, so `$args.Count -gt 0` held and the sequence-aware filter reported an argument that does not exist. The published inventory had been carrying three such false redactions (`claude-code` figma, `codex-cli` cua_repl, `qoder` GitHub — all three are url-only servers, verified in the real config files). Nulls are now dropped before the filter.
- **`[]` was a parse failure.** The YAML subset reader threw on a document that is exactly `[]`. That is a complete YAML document meaning "no entries" and it is precisely what DSH's profile template writes into a fresh `cordis.patch.yml`, so the reader now returns an empty list.

Both are covered by the new fixture `tests/fixtures/config-profiles/mcp/dsh/` (a home-level `[]` layer and a profile layer with a remote server, a stdio server, a non-MCP-client decoy row and a `headers` block) and by the new test *"DSH patch-layer MCP servers are projected per profile without headers"*.

## Canonical changes from this round

- `context/configs/mcp.json` — new `dsh` server `parallel` (scope `web`, transport `streamable-http`, url `https://search.parallel.ai/mcp`); the stale `dsh` unresolved entry removed; both DSH patch layers recorded as `mcp-config` source files; `redactions` now empty after the false ones were corrected. Produced by the routine collector.
- `context/software/ai.json` — routine drift only: **agy 1.2.10 → 1.2.11** (`agy --version` reports 1.2.11; `%LOCALAPPDATA%\agy\bin\agy.exe` mtime 2026-09-26 15:25). This upgrade happened outside this session and was not performed here.
- `context/machine.json` — routine disk free-space drift only (`D:\` −0.25 GiB).
- `context/status.json` / `CURRENT.md` — heartbeat, plus the rendered MCP line now reading `dsh (1)`.
- `context/configs/ai/dsh.json` — unchanged, and correctly so: it projects `settings.yaml`, which was not modified, and DSH's MCP declarations belong to the MCP inventory rather than to that profile.

## Gates

`tests/run-tests.ps1` → all tests pass, including the new DSH MCP test. `sync.ps1` → overall health `success`, all 10 providers `success`, validation `ok`, 0 warnings. `validate.ps1` → `{ok: true, errors: [], warnings: [], findings: []}`. A second sync was idempotent: of 29 canonical files only `context/status.json` and the `CURRENT.md` it renders changed, both heartbeat-only.

## Known limitations left in place

- **Anonymous tier.** The MCP is fully usable but runs on Parallel's free tier. Moving to the paid quota needs `PARALLEL_API_KEY` made visible to the DSH process first; the patch file carries the exact one-line header to add at that point, commented out, and no literal secret is ever to be written there.
- **`reasoning`-style provider-specific fields are out of scope for the inventory.** The collector records endpoint, transport and tool-relevant shape only.
