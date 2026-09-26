# Devlog — 2026-09-26 ZCode TokenRhythm GLM-5.3 configuration + stale desktop entity audit

Scope: add the plain `glm-5.3` model to the existing TokenRhythm (基元律动) provider in ZCode's active config, verify it against the provider's real model directory and a live request, then record the change in MachineContext. The repository sync produced no other semantic drift, but the audit that §8 requires for supplementary desktop entities found five of them stale and they were refreshed in the same publish.

DSH was not touched. No other tool was installed, upgraded or reconfigured.

## What was configured

ZCode's active config is `D:\ZCode\appdata\.zcode\v2\config.json` — confirmed still correct: the live app writes its settings to `%USERPROFILE%\.zcode\v2\setting.json`, which carries `"dataBaseDir": "D:\\ZCode\\appdata"`, and the `%USERPROFILE%\.zcode\v2\config.json` copy is still only recorded as `sensitive-config-copy` and never parsed.

Adding a usable model required **two** files, because ZCode keeps model metadata and provider rules separately:

| File | Change |
| --- | --- |
| `D:\ZCode\appdata\.zcode\v2\config.json` | new `provider.<tokenrhythm>.models["glm-5.3"]` entry (metadata: reasoning / limit / modalities) |
| `D:\ZCode\appdata\.zcode\v2\provider_config.json` | `personalModelIds` + `modelOrder` gained `glm-5.3`; a `providerModelRules` entry set `contextWindow` |

Everything else was left byte-identical: provider, API key, base URL, default provider/model, and the pre-existing `glm-5.3-flash` entry. One backup per file was taken before the edit (`config.json.bak-20260926-glm53`, `provider_config.json.bak-20260926-glm53`), following the app's own `.bak-<timestamp>` convention.

## How the parameters were established (not copied from Flash)

The sibling `glm-5.3-flash` entry was used only as the **structural** reference. TokenRhythm's own model directory was treated as the authority, per the round instruction, and it turned out to disagree with Flash on two of the four fields:

`GET https://tokenrhythm.studio/api/v1/models` (the `/v1/models` variant returns ids only; `/api/v1/models` returns the full record):

| Field | `glm-5.3` (new) | `glm-5.3-flash` (existing) | Source |
| --- | --- | --- | --- |
| `context_length` | **1048576** | catalog says 1048576, ZCode entry says 1050000 | TokenRhythm directory |
| `max_completion_tokens` | **131072** | 131072 | directory + server-side validation |
| `supports_vision` | **false** | true | directory + live probe |
| `supports_reasoning` | true | true | directory |

Live probes against `https://tokenrhythm.studio/v1/chat/completions` (text-only) confirmed the output cap independently: `max_tokens=131072` → HTTP 200, `max_tokens=131073` → `400 LITELLM_ERROR "[max_tokens should be less or equal to 131072]"`.

**Multimodality differs from Flash, and this is the load-bearing finding.** A controlled A/B sent the same small test image (the literal text `ZEBRA-4417`) to both models:

- `glm-5.3-flash` → read the image correctly;
- `glm-5.3` → `400 {"code":"MODEL_CAPABILITY_NOT_SUPPORTED","message":"当前模型不支持该能力：vision"}`.

So `glm-5.3` is projected text-in/text-out, and the Flash entry's `["text","image","video"]` must not be assumed to hold for the non-Flash model. This also matches ZCode's own bundled catalogue (`resources/config/provider/zcode-builtin.json`), which lists `GLM-5.3` with input `["text"]` while `GLM-5.3-Flash` carries image and video.

Two caveats recorded for future rounds:

- **The gateway does not validate `reasoning_effort`.** Arbitrary values (`bogus_xyz`) are accepted with HTTP 200, so the accepted effort set cannot be derived from error responses. The variants `low`/`high`/`max` were taken from the same provider's Flash entry and ZCode's built-in `GLM-5.3` metadata, and `max` is the `defaultVariant` per the user's stated preference. Reasoning does run: responses carry `reasoning_content` and `completion_tokens_details.reasoning_tokens`.
- **The existing Flash entry's context value (1050000) disagrees with TokenRhythm's directory (1048576)** for both models. Flash was deliberately left untouched this round, so the two sibling entries now differ by 1424. Aligning them is a user decision.

## Verification performed

- both edited files parse as JSON and the collector projects them;
- provider/credential/base URL unchanged, `credential_configured: true` still the only credential trace;
- `glm-5.3` appears in both `config.json` and `provider_config.json` (`personalModelIds` / `modelOrder` / `contextWindow` rule);
- live smoke request with the configured values (`reasoning_effort=max`, `max_tokens=131072`) → HTTP 200, returned `model: glm-5.3`, content `OK`, `finish_reason: stop`;
- no ZCode restart was required: the running instance re-read provider settings **after** the write (log `provider-settings.refresh OK (792.2ms)` at 12:12:45 vs. the 12:09:33 config write), and the provider repository re-reads the file from disk on each call. Note `closeToTrayOnWindows: true`, so closing the window does **not** reload — a full quit would be needed if a reload were ever required.

## Canonical changes from this round

- `context/configs/ai/zcode.json` — `glm-5.3` added under the TokenRhythm provider (`limit.context` 1048576, `limit.output` 131072, input/output `["text"]`, reasoning enabled with `low`/`high`/`max` and default `max`). Pure addition, produced by the routine collector from the real config file — the projection was **not** hand-edited.
- `context/software/ai.json` — the §8 desktop entity refresh below.
- `context/machine.json` — routine disk free-space drift only (C: +0.5 GiB, D: −0.8 GiB, E: −0.3 GiB).
- `context/status.json` / `CURRENT.md` — heartbeat only.

## Supplementary desktop entity audit (OPERATIONS §8)

The ZCode drift found while working on the config change prompted the full §8 comparison — registry `DisplayVersion` and executable `FileVersion` for every desktop entity, not just path existence. Five had silently gone stale and were refreshed by a one-time script (`.local/refresh-2026-09-26-desktop-entities.ps1`); all executable paths were unchanged.

| Entity | Before → After | Evidence |
| --- | --- | --- |
| zcode | 3.14.0.7681 → **3.14.3.7762** | exe FileVersion/ProductVersion 3.14.3.7762 (mtime 2026-09-22); HKCU uninstall "ZCode 3.14.3"; active runtime dir `...\windows-x86_64\3.14.3` |
| antigravity-desktop | 2.11.0 → **2.17.0** | exe FileVersion 2.17.0 (mtime 2026-09-23); HKCU uninstall "Antigravity 2.17.0" |
| qoder | 0.3.4 → **0.4.2** | live process resolves to `.qoder-versions\0.4.2\Qoder CN.exe`; that payload's `build-manifest.json` reports productVersion 0.4.2; registry now also 0.4.2 |
| workbuddy | 5.3.14 → **5.5.6** | exe FileVersion 5.5.6 (mtime 2026-09-10); HKCU uninstall "WorkBuddy 5.5.6" |
| doubao-work | 2.25.18 → **2.30.5** | exe FileVersion 2.30.5 (mtime 2026-09-21); HKCU uninstall "豆包工作" 2.30.5 |

Verified unchanged and therefore not touched: agy 1.2.10, trae 0.1.58, wand 12.21.0, cherry-studio 1.8.1, open-design 0.16.1, cursor-cli 3.8.11, claude-desktop 1.37937.3.0 (MSIX), codex-desktop 26.917.9434.0 (MSIX).

**One entity was deliberately left alone.** `doubao` has conflicting evidence: the recorded `2.25.16` comes from the HKCU uninstall entry "豆包", which still reads 2.25.16, while `D:\Doubao\Doubao.exe` reports FileVersion 2.26.10 (`D:\Doubao\app\Doubao.exe` reports 147.0.7727.149, which is the bundled Electron shell, not the product). There is no versioned payload directory or build manifest to break the tie and the app was not running during the audit, so rather than promote a guess the entity was left at the registry-derived value and the conflict recorded in its curated notes. It needs a user confirmation or a live-process reading.

## Gates

`sync.ps1` → overall health `success`, all 10 providers `success`, validation `ok`; `validate.ps1` → 0 errors / 0 warnings / 0 findings; second sync idempotent (only the `verified_at` heartbeat moves); privacy sweep over the added diff lines clean — the only credential trace anywhere is `"credential_configured": true`, and no API key value, token or opaque string from any config file entered the repository.
