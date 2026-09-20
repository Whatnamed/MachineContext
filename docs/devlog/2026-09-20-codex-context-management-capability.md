# Devlog — 2026-09-20 Codex `features.context_management` enabled, and the capability gate that keeps it inactive

Scope: enable Codex's experimental context management in the shared `%USERPROFILE%\.codex\config.toml`, verify whether `gpt-6-astra` actually gains the capability, then run the routine sync. The config edit landed and is effective at the feature-flag layer; the **model-level capability gate is still closed**, so experimental context management is not actually active for Astra.

## Config change

- File: `%USERPROFILE%\.codex\config.toml` — shared by Codex CLI and Codex desktop (`CODEX_HOME` points at the same directory).
- Backup before the edit: `config.toml.bak-before-context-management-20260920-185355`, sha256 `1945B02F…A65A926`.
- Exactly three lines were added inside the existing `[features]` table. A unified diff against the backup shows no other change:

```toml
[features]
fast_mode = true
memories = true

[features.context_management]
experimental_mode = true
```

- `[features.context_management]` did **not** exist before, so this was a pure add, not a merge over existing values. `fast_mode` and `memories` are untouched.

### The table form is real config, not a no-op

Verified against codex-cli 0.154.0 before relying on it:

| Probe | Effective `context_management` |
| --- | --- |
| `-c features.context_management=true` | `true` |
| `-c 'features.context_management={experimental_mode=true}'` | `true` |
| `-c 'features.context_management={experimental_mode=false}'` | `false` |
| `-c 'features.context_management={}'` | `false` |
| `-c 'features.context_management={nonsense=1}'` | `Error: failed to load bootstrap configuration … in 'features.context_management'` |

The rejected unknown key proves the field is schema-validated rather than silently ignored. Corroborating binary evidence: `struct ContextManagementConfigToml with 1 element` (field `experimental_mode`), and feature values deserialize through an untagged `FeatureToml` enum that accepts **either** a bool **or** a config struct.

Effective state after the edit: `codex features list` → `context_management  under development  true`. Stage is `under development`, i.e. a dev-stage flag, not a stable feature.

## Capability check: `gpt-6-astra` does **not** have experimental context enabled

The feature flag is on; the model capability is not. Both the live catalog and the cached catalog agree:

`codex debug models` (codex-cli 0.154.0, rendered live):

| slug | `supports_experimental_context` | context_window / max |
| --- | --- | --- |
| gpt-5.6-sol | false | 272000 / 272000 |
| **gpt-6-astra** | **false** | 272000 / 872000 |
| gpt-reserve | false | 272000 / 872000 |
| gpt-5.6-terra | false | 272000 / 872000 |
| gpt-5.6-luna | false | 272000 / 872000 |
| gpt-5.5 | false | 272000 / 272000 |
| codex-auto-review | false | 272000 / 872000 |

`%USERPROFILE%\.codex\models_cache.json` (fetched 2026-09-20T10:49:55Z by client 0.155.0) reports `false` for the same seven slugs. The desktop-bundled 0.155.0-alpha.9.2 binary renders an identical catalog. So this is not a stale-cache artifact and not a per-model gap for Astra alone — **every** model in the current catalog reports `false`.

Behavioral confirmation, rather than inference from the flag alone: `codex debug prompt-input "probe"` was rendered with the flag on and with `-c features.context_management=false`. The two outputs differ **only** in message ids and `create_time` values (10 lines each way, all metadata). No context-management instruction, and no `new_context` / `get_context_remaining` / `notes` tool, appears in the model-visible input in either run.

Conclusion for this version: enabling `features.context_management.experimental_mode` flips the harness feature flag but does not deliver the capability to `gpt-6-astra`, because the model catalog gates it with `supports_experimental_context = false`. This is a capability regression relative to what the flag name implies — recorded as a finding, not worked around. Note the 0.154.0 binary also embeds a sample catalog entry showing `"slug": "gpt-6-astra"` with `"supports_experimental_context": true`, so the field is expected to be `true` for Astra in some client/catalog combination; the catalog this machine actually receives says otherwise.

## Stale 0.130.0 binary in the Codex app data tree — identified, then deleted

While verifying the edit, `%LOCALAPPDATA%\OpenAI\Codex\bin\codex.exe` (`codex-cli 0.130.0-alpha.5`, written 2026-05-09, 245,812,016 bytes) turned out to fail on the edited config:

```
Error: C:\Users\hasee\.codex\config.toml:194:1: invalid type: map, expected a boolean
Caused by:
    invalid type: map, expected a boolean
    in `features`
```

Its `FeatureToml` predates the untagged-enum form and accepts booleans only. The Codex app data tree uses a content-addressed layout — `bin\<hash>\` per component — and this file sits at the **root** of `bin\`, beside an equally old `node.exe` (2026-04-17), `node_repl.exe` (2026-05-08), `codex-command-runner.exe` / `codex-windows-sandbox-setup.exe` (2026-05-09) and `rg.exe` (2026-03-18). All of them are remnants of the pre-hash-directory layout.

Deletion was preceded by a reference search, not by the version mismatch alone:

- no text file under `%LOCALAPPDATA%\OpenAI` mentions `OpenAI\Codex\bin\codex.exe` (0 hits), including the stale `chrome-native-hosts.json`, which points at a `bin\7dea4a003bc76627\codex.exe` that no longer exists and is superseded by the empty `chrome-native-hosts-v2.json`;
- no mention in `%USERPROFILE%\.codex` (`.codex-global-state.json`, `config.toml`, `session_index.jsonl`, `version.json`, plus depth-2 config files): 0 hits;
- not on PATH — the only Codex PATH entry is `E:\Codex\codex-cli`;
- no Start Menu / Desktop shortcut targets anything under `OpenAI\Codex`;
- no running process resolves from it; the live `codex` process (pid 5000) runs `bin\247581e40ee272fb\codex.exe`, which is also what `config.toml` names via `CODEX_CLI_PATH`.

Deleted 2026-09-20 (sha256 `DD4ADF30…0A6B3E3E`, 245,812,016 bytes). Verified after: `codex --version` → 0.154.0, all desktop `codex`/`node_repl`/`ChatGPT` processes still running from their versioned paths. A `sync.ps1 -NoPublish` dry run then reported `changed_files: []` and a clean `git_status`, confirming no collector observes that path — the deletion required no canonical re-publish.

Not deleted: the five sibling root-level binaries listed above. They are the same category and equally unreferenced, but they were outside what was asked, so they are left in place and flagged instead.

## Incidental real drift captured by the same sync (not caused by this round)

- **Codex CLI profile** `gpt-5.6-luna` / `model_reasoning_effort = max` → `gpt-6-astra` / `high`. This is the drift the sync was run for; it was already true on disk before the edit.
- **qoder `mcp-router.json`** `exists` true → false. Qoder CN 0.3.4 **is** running (pid 18232, started 17:20:38), yet the file is absent everywhere under `.qoder-cn`. That weakens the 2026-09-19 claim that presence "tracks whether the app is running": the correct reading is that it is runtime-transient and lazily written, so **neither** reading implies removal. No curated text asserts a mechanism this round, so no in-place correction was needed.
- **User PATH** 37 → 41 entries: four `E:\CS2MOD\wt-agent-{a,b,c}\.cache\…\.dotnet\tools` paths added by the CS2MOD agent worktrees (directories created 2026-09-20 00:42–07:24). None of the four directories exists on disk yet — the same sentinel-created-but-not-yet-materialized pattern as the `.dotnet\tools` entry recorded on 2026-09-19.
- Storage heartbeat on C:/D:/E: (E: free fell 134.8 → 102.0 GiB).

## Collection gap (deliberately not closed this round)

`COLLECTION_SPEC.md` §AI-harness projections and `OPERATIONS.md` §4.1 fix the codex-cli profile contract at five **top-level scalar** keys. `Get-McCodexConfigProfile` reads via `Get-McTomlTopLevelScalars`, so `[features]` — a table — is neither projected nor recorded in `unprojected_keys`. The setting this round enabled is therefore **invisible to canonical**: the sync diff shows the model change but cannot show that experimental context management was turned on.

Closing that would mean changing the collection contract (allowlist shape, fixture, tests, spec), which is a spec-level decision rather than a side effect of this task. Left open and flagged instead of being folded in silently.

## Canonical

- Routine provider refresh: `context/configs/ai/codex-cli.json` (model, reasoning effort), `context/configs/ai/qoder.json` (`mcp-router.json` existence), `context/machine.json` (PATH entries, storage heartbeat), `context/status.json` + `CURRENT.md` (heartbeat).
- No curated change, no collector change, no schema change, no new entity this round.
- `%USERPROFILE%\.codex\config.toml` itself is **not** tracked by this repository; only its allowlisted projection is.

## Gates

- `sync.ps1` (Quick): all ten providers `success`, validation ok, published.
- `git diff` reviewed line by line; every canonical change is accounted for above.
- `validate.ps1`: 0 errors, 0 warnings, 0 findings.
- `tests/run-tests.ps1`: all tests passed (run although not required — no collector or test code changed).
- Second sync idempotent: `git diff` of the two runs differs only in the `verified_at` heartbeat in `context/status.json` and `CURRENT.md`; every canonical data file byte-identical.
- Third sync, `-NoPublish` dry run after the stale-binary deletion: `changed_files: []`, clean `git_status`, validation ok — the deletion introduced no canonical drift.
- Privacy sweep over `git diff context/`: no `sk-`, `bearer`, `authorization`, `opaque`, `secret`, `password`, or private-key shapes. The single `token` hit is the `model_auto_compact_token_limit` field name.
