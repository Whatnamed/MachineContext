# Devlog — 2026-09-16 OMP 18.1.21 → 18.2.1 upgrade, and why OMP never loaded the global ruleset

Scope: apply the previously-assessed-but-not-executed OMP upgrade, prove it landed in the correct install root, and re-check that the shared global ruleset reaches OMP. The re-check falsified an earlier claim, exposed the silent gate that caused it, and the gate was then fixed and re-verified. It also records the methodology error that hid the problem for a full round.

## Upgrade

| Item | Value |
| --- | --- |
| Before | 18.1.21 (`D:\OMP\omp.exe`, 161,703,936 bytes, sha256 `61856ACA…C45DA`) |
| After | **18.2.1** (`D:\OMP\omp.exe`, 211,734,016 bytes, sha256 `FEE52652…966679`) |
| Mechanism | `omp update` — in-place, updater-reported sha256 accepted only after its own verification (`Verified sha256:fee52652…`) |
| Backup | `omp.exe.1789534362039.11444.0.bak` (the pre-update 18.1.21 binary, hash confirmed unchanged) |
| Size delta | 161.7 MB → 211.7 MB, consistent with the 18.2.0 change to ship precompiled bytecode |

- **Location discipline.** The machine has a history of an updater creating a *second* install (`claude update` once populated `E:\Dev\npm-global`). Before updating, the target was pinned: `Get-Command omp -All` resolved to exactly one entry, and no `omp.exe`, `omp.cmd`, or npm shim existed under `E:\Dev\npm-global`, `%APPDATA%\npm`, or `~/.omp`. After the update, the same checks were repeated — still exactly one resolution at `D:\OMP\omp.exe` and no shim anywhere. The updater printed the destination explicitly, which matches.
- **Lock handling.** Three `omp` processes were live (main session PID 6396 started 00:10 plus its `__omp_worker_js_eval_process` and `__omp_worker_daemon_broker` children); Windows cannot replace a locked exe. The user closed them, the exe was confirmed unlocked with an exclusive-open probe, and only then the update ran. Sessions are persisted, so they remain resumable.
- Configuration carried over untouched (`config.yml`, `models.yml`, `setupVersion: 2`); no legacy `settings.json` migration was pending — only the already-archived `settings.json.bak` from the earlier migration remains.

## The correction: how "global rules load" was verified

The 2026-09-15 round recorded that OMP picks up the user-level ruleset from `%USERPROFILE%\.codex\AGENTS.md`, "verified via `omp -p`, reproduced the six section headings". **That verification was invalid.** It was run from inside `E:\MachineContext`, which owns its own `AGENTS.md`. The model reproduced *that* file's headings (`## Purpose`, `## Read first`, …), which proves project-level injection works and says nothing about the user-global file.

Re-tested properly from a scratch directory containing `.git` but **no** `AGENTS.md`:

| Binary | Result from scratch project |
| --- | --- |
| 18.2.1 | no injected instruction file (answered `NONE`) |
| 18.1.21 (controlled A/B: parked 18.2.1, restored the saved `.bak`, then restored 18.2.1 and re-verified its hash) | no injected instruction file (answered `NONE`) |

## Root cause and fix (resolved in the same session)

The loader for this source is readable in the bundled `omp.exe` source:

```js
function R7(e) { return path.join(e.cwd, ".codex"); }
function g3(e, t = false) {
  if (!t && !dl("codex", e)) return null;          // <-- the gate
  return path.join(e.home, d8.codex.userBase);
}
async function Mll(e) {
  const o = g3(e);
  if (!o) return { items: [], warnings: [] };      // short-circuits silently
  const n = path.join(o, "AGENTS.md");
  ...
}
function dl(e, t) {
  const s = e.replace(/^\./, "");
  if (pC.has(s)) return false;                                    // disabledProviders
  if (X4s[s] !== true) return true;                               // default-on provider
  if (t?.explicitProviders?.has(s) || t?.includeOptOutUserSources) return true;
  if (Dk.has(s) || Dk.has("*") || Dk.has("all")) return true;      // enabledProviders
  return false;
}
```

`codex` is an **opt-out** context-source provider: it is not default-on, so it only loads when explicitly enabled. `omp config get enabledProviders` returned `[]`, so `g3` returned `null`, `Mll` returned an empty item list, and the source contributed nothing — **with no warning at all**, which is why this looked like a working feature for a whole round.

- **`provider` here means a context-source provider id, not an LLM provider.**
- **Fix:** `omp config set enabledProviders '["codex"]'`. The value must be a JSON array — a bare `codex` is rejected with `Invalid array JSON`. This wrote a top-level `enabledProviders: [codex]` to `%USERPROFILE%\.omp\agent\config.yml` (1046 → 1074 bytes); the pre-change file is saved at `.local/backup-omp-config-2026-09-16.yml`.
- Enabling it also activates the sibling Codex-compat sources (`~/.codex/skills`, `extensions`, `commands`, `prompts`, `hooks`, `tools`). None of those directories exist on this machine — only the global `AGENTS.md` is present — so there was no other effect.

**Post-fix verification.** With no overlay, asking for `COUNT`/`LANG` (ASCII-only answers, to avoid console encoding noise):

| Directory | Result | Meaning |
| --- | --- | --- |
| scratch project, `.git` only | `COUNT=6 LANG=chinese` | the shared global ruleset now loads (was `NONE`) |
| `E:\MachineContext` | `COUNT=6 LANG=english` | the project file is what reaches the model |

So OMP surfaces the **project-level** `AGENTS.md` instead of the user-global one rather than concatenating both. The bundled descriptor "(user-level only)" reads consistently with that, but whether this is deliberate precedence/dedup or merely first-match was **not** proven and is not asserted here.

So this is **not** a regression introduced by the update — the user-global file was never reaching the model, on either version.

- The bundled context-source descriptor exists in 18.2.1 and reads: *"Load context files from ~/.codex/AGENTS.md (user-level only)"*, registered alongside the other Codex-compat sources. A source being registered is not sufficient for it to contribute content — it also has to pass the per-provider opt-in gate above.
- OMP session transcripts do not persist the system prompt (a headless run writes ~7 records: title/session/model_change/two messages/credential_pin/session_exit), so transcript grepping cannot settle this class of question — a behavioural test is required. That is also why the earlier round's mistake was invisible from the session log.

## Canonical

- Routine provider refresh: `omp` 18.1.21 → 18.2.1. Also captured by the same sync, unrelated to this work: `C:\` free space 22,011,707,392 → 21,743,271,936 bytes (the update's download/staging churn).
- Curated (`.local/curated-2026-09-16-omp-upgrade.ps1`): the upgrade record with hashes, the duplicate-install guard result, and the global-rules finding.
- Curated fixes (`.local/fix-2026-09-16-omp-note-replace.ps1`, `.local/fix-2026-09-16-omp-root-cause.ps1`): the stale and then-unresolved sentences were **rewritten in place** each time rather than left beside newer notes, so the canonical record never asserts two contradictory states of the same fact.
- The 2026-09-15 devlog's OMP row is marked RETRACTED with the reason, and a method note was added to that entry covering every row of its table.
- Machine config changed by this work: `%USERPROFILE%\.omp\agent\config.yml` gained top-level `enabledProviders: [codex]`. Backup at `.local/backup-omp-config-2026-09-16.yml`.

## Gates

- `sync.ps1 -AllowDirty`: all ten providers success, validation ok (0 warnings, 0 findings).
- `tests/run-tests.ps1`: not re-run — no collector, lib, or test changes in this round (the version came from the existing provider).
- Post-upgrade smoke: `omp/18.2.1`; `omp models` resolves the provider catalog (20 `google-antigravity` models listed, including the configured `gemini-3.8-flash`); a headless turn completed normally against the configured default model.
- Fix verification used ASCII-only answers (`COUNT=`/`LANG=`) specifically to avoid console encoding noise; the behavioural matrix (baseline / `codex` / `claude` / `cursor`) was re-run cleanly to rule out a fluke before the config was persisted.
- Self-inflicted artifacts cleaned: all scratch projects (`E:\Dev\oprobe*`), overlay and result files, and the temporary OMP package download removed; no parked binary left in `D:\OMP`.
