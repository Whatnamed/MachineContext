# Devlog — 2026-09-30 DSH config profile on Cordis layers + confirmed-absence source contract

Follow-up round on the two DSH config defects left open by `2026-09-30-ai-tooling-maintenance.md`. Scope was strictly those two problems: no software upgrades, no DSH version or command-ownership change, no other CLI re-audit, and no writes into the real `%USERPROFILE%\.dsh`. Baseline `main` = `10d5dbf`.

## 1. Root cause of the self-contradictory stale record

`context/configs/ai/dsh.json` claimed `observed.source_state: stale` with `source_state_reason: "config source confirmed absent during scan"` while `source.files[]` still reported the deprecated `%USERPROFILE%\.dsh\settings.yaml` with `exists: true`.

The defect was generic, not DSH-specific. The `config-profiles` provider reported a confirmed absence as only `{tool, state}`, and the `source-missing` branch of `Merge-McConfigProfiles` (scripts/lib/reconcile.ps1) rewrote `observed.source_state` / `source_state_reason` on the retained record **without touching `source.files[]`**. Every other field of that record — including the existence flags written by an earlier scan when the file was still there — was carried over verbatim. So the record that documented "the source is gone" kept asserting the source exists.

## 2. Generic reconciliation contract

The internal payload now carries the minimal metadata the collector is already able to prove, instead of the reconciler guessing paths per tool:

- `profile_states` entry shape: `{tool, state: 'source-missing', missing_sources: [...]}`, where `missing_sources` are normalized paths the collector actually probed and found absent.
- `Get-McConfigSourceProbe` (scripts/lib/config-projection.ps1) produces `{path, normalized_path, exists}` records and skips a candidate without a directory part, which is how an unset config root degrades to "no source probed" rather than a bogus relative path.
- Every projector in `Get-McConfigProfileObservations` now declares the sources its projection is built on; presence is "at least one declared source exists". This replaced six ad-hoc `$xPresent` booleans and made the absence report uniform across OMP / DSH / ZCode / OpenCodex / codex-cli / Qoder.
- `Merge-McConfigProfiles` calls the new `Update-McStaleProfileMissingSource`, which demotes `source.files[].exists` to `$false` **only** for listed paths.

Deliberate properties, all covered by tests: a path the collector never probed keeps its recorded existence (no blanket demotion); a `failed` state leaves the last-known record byte-identical, so parser/provider failure stays distinguishable from confirmed absence; the last-known projection and `curated` notes are preserved; a state without `missing_sources` behaves exactly as before (the pre-existing tests still pass unchanged); demotion is byte-idempotent across repeat scans; and a fresh profile for the same tool still wins over a stale state.

One zero-set boundary in that new contract needed a second pass: the absence test was written as `missingSources.Count -eq sources.Count`, so a projector with **no probeable source at all** (an unset config root, which `Get-McConfigSourceProbe` deliberately skips) satisfied `0 == 0` and was published as a confirmed absence — the exact inverse of what `source-missing` now means. Such a projector reports `failed` with a "no config source path could be probed" warning instead, which keeps the last-known record untouched and degrades provider health to `partial` rather than silently stamping it stale. No production default has an empty source set, so this changed no canonical record; the regression test drives the provider with a blank DSH root and asserts both the reported state and that an existing `dsh.json` survives the merge byte-identical.

## 3. Real DSH config-model audit

Evidence was the shipped loader in `D:\DSH-desktop\resources\app.asar` plus the live files, read through value-class skeletons only — no config values were printed while designing the allowlist.

- `collectConfigDumpLayers` reads layers "in bundle, profile, home, then argv order", and `homePatchPath()` is documented as "the home-level user patch layer (`$DSH_HOME/cordis.patch.yml`), applied over every profile's own layer". A later layer overrides an earlier entry with the same id.
- A profile's `cordis.yml` is the empty root those patches overlay; the file header itself says "Edit cordis.patch.yml, not this file". It is therefore **not** a config source.
- Profile selection happens per invocation and **no active profile is persisted**, so there is no single composed "current configuration" to publish.
- On this machine: home layer is `[]` (3 B, participates but contributes nothing); `profiles\desktop\cordis.patch.yml` (3897 B) holds the LLM config actually in use; `profiles\web\cordis.patch.yml` (3813 B) is 17 `disabled: true` rows plus one `insert` block whose MCP row carries a `headers` Authorization expression; `profiles\node_modules` is a pnpm install tree, not a profile; `.agent-presets` exists and is empty; `settings.yaml` is gone and `settings.yaml.imported` (2454 B) is the product's renamed import; `%USERPROFILE%\.dsh\.env` and `.credentials.yaml` exist and were never opened.
- Where the previously projected semantics went: `agent-default-model` (now also carrying `reasoningEffort`), `llm-pi-ai` (`providers.*` with `apiKeyEnv` env-var names) and `llm-deepseek` (`baseURL` + `models[]`) survive as Cordis entries **with the same ids and the same config shape**; `compat` under a model is still unprojected; the settings.yaml `agent-presets:` section no longer exists and `.agent-presets` has no entries, so there is nothing to project.

## 4. Projector migration

`Get-McDshConfigProfile` now reads the patch layers through the existing machinery: the repo's YAML subset parser (`Read-McConfigYaml`), the per-field allowlist walker, the safe-url/credential-env helpers, `Get-McCredentialEnvNamesFromProjection`, and `New-McConfigProfileRecord`. No second Cordis parser was added — the MCP inventory and the config profile share one layer-discovery function, `Get-McDshCordisPatchLayers`, which returns layers in composition order and marks a directory as a profile only when it carries a `cordis.yml` or a `cordis.patch.yml`.

Source model: `source.files[]` lists every participating patch layer (role `cordis-patch-layer`), `.credentials.yaml` (role `credential-file`, path/exists only), `.agent-presets` (role `agent-preset-directory`), and `settings.yaml.imported` (role `imported-legacy-config`, recorded as historical evidence and never parsed). The deprecated `settings.yaml` is no longer a source at all. A layer that fails to parse makes the projector throw, so the driver records `failed` and the last-known record stays untouched — absence and breakage remain distinct outcomes.

Privacy boundary, unchanged in principle and re-checked for the new shape: only `entries` subtrees of allowlisted entry ids are read; `agent-default-model` and `llm-*` are the only projected ids; `apiKeyEnv`/`apiKey` may survive only as `credentialEnvName`; `baseURL` goes through safe-url normalization; `ui-*`, `permission`, `live-stats` and MCP rows are never walked, and every entry deliberately not projected still appears as an id in `unprojected_entry_ids`, while allowlist-dropped fields appear in `unprojected_keys`. The allowlist was **not** widened because the old profile had those fields.

## 5. Canonical outcome

`context/configs/ai/dsh.json` went from `stale` (last-known settings.yaml snapshot, `source.files` contradicting it) to `current` with the Cordis projection: `layer_order` `bundle → profile → home → argv`, three layers (desktop with `agent-default-model` / `llm-pi-ai` / `llm-deepseek`, web contributing ids only, home present and empty), `credential_env_names` `AIJWS_API_KEY`, `OPENAI_API_KEY`, `TOKENRHYTHM_API_KEY`, `unprojected_keys` for `…tokenrhythm.models[1].compat`, `redactions: []`, and all six source files with `exists: true` matching the real disk state. `context/configs/index.json` reports `current` and CURRENT.md dropped the `(stale: config source missing)` suffix. `mcp.json` changed only in the ordering of the three DSH patch-layer source entries, because both collectors now emit composition order.

## 6. Verification

1. `tests/run-tests.ps1` — all blocks pass. Ten DSH fixture cases cover: profile+home overlay; the home layer overriding a profile value; provider/model/reasoning/baseURL/modality/maxTokens projection; an inline fake API key; an env-var credential; unknown provider fields and unprojected entry ids; an empty `[]` layer; a missing patch layer; a malformed layer; and the legacy `settings.yaml` + `settings.yaml.imported` pair that must not be promoted. Every fake value (`fake-refresh-token`, `sk-test-do-not-publish`, `sk-legacy-import-do-not-publish`, `user:pass` userinfo, `trace-value-not-allowlisted`, `FIXTURE_MCP_TOKEN`, `Bearer`, the fixture MCP URL, the unprojected UI/permission values) is asserted absent from the serialized projection, plus `Get-McSensitiveConfigKeyFindings` = 0. Two new reconciliation blocks cover the demotion contract and the driver's `missing_sources` payload.
2. Building the fixtures found a real leak path: a fixture provider id ending in `secret` (`inlinesecret`) is itself rejected by `Test-McSensitiveConfigKeyName`, so it could not be published even with a clean config. The fixture was renamed to `inlinekey` rather than the denylist weakened.
3. Reconciliation coverage is one new driver-level block (`config profile observations name the sources they proved absent`) plus the extended stale-reconciliation block, which now also asserts the `failed` case, the legacy payload without `missing_sources`, and a fresh profile winning over a stale state.
4. `sync.ps1` — overall health `success`, all providers `success`, validation `ok`, 0 warnings. `validate.ps1` — 0 errors / 0 warnings / 0 findings.
5. Second sync idempotence — SHA-256 over all 28 `context/` files: only `context/status.json` (the heartbeat) changed.
6. Privacy sweep over the added canonical lines — no credential shapes (`eyJ…`, bearer, private-key, userinfo URLs, credential assignments), no literal user profile path or account name. The single regex hit was `web-ui-task-board` matching `sk-` inside "task-board".
7. Curated notes on `dsh.json` were rewritten through the documented one-time curation path (`.local\curate-dsh-cordis-2026-09-30.ps1`), because the two previous notes described the stale state and the open follow-up. They now document the layer model, why layers are not composed, and what is owned by `mcp.json`.

## 7. Docs

`OPERATIONS.md` §4.3 rewritten for the implemented Cordis source model (sources, layer precedence, projected entry ids, what stays unprojected, and the easy-to-miss items: `[]` layers are legal, parse failure ≠ absence, layer discovery is shared with `mcp.json`); §8 stale-semantics bullet extended with the `missing_sources` demotion contract. `COLLECTION_SPEC.md` gained the DSH per-tool source paragraph and the confirmed-absence refresh rule. `SCHEMA.md` documents the layered projection shape and the new reconciliation contract.

## 8. Unrelated observations (not fixed, by scope)

- `%USERPROFILE%\.dsh` also contains `.env`, `pet.json`, `skin-center-active.json`, `storages\`, `task-board\`, `sessions\`, `attachments\` — none are MachineContext sources and none were read.
- The DSH `permission` entry (`profiles\desktop\cordis.patch.yml` declares presets such as `read-only` / `workspace-write` / `danger-full-access` plus a `defaultPreset`) currently sits unprojected by design; it is safety-relevant semantics, and a future round that wants it needs its own allowlist decision rather than widening the LLM one. The value of `defaultPreset` was deliberately not read while auditing, so no claim is made here about which preset is active.
