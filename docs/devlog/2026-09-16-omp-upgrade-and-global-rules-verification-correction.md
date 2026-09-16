# Devlog — 2026-09-16 OMP 18.1.21 → 18.2.1 upgrade, and a correction to how global-rules loading is verified

Scope: apply the previously-assessed-but-not-executed OMP upgrade, prove it landed in the correct install root, and re-check that the shared global ruleset still reaches OMP. The re-check falsified an earlier claim, so this entry also records the methodology error behind it.

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

So this is **not** a regression introduced by the update — the user-global file was evidently never reaching the model. Injection from a project directory does work on the same 18.2.1 binary.

- The bundled context-source descriptor still exists in 18.2.1 and reads: *"Load context files from ~/.codex/AGENTS.md (user-level only)"*, registered alongside other Codex-compat sources (`~/.codex/skills`, `config.toml [mcp_servers.*]`). A source being declared is evidently not sufficient for it to contribute content.
- **Unresolved, and deliberately not asserted:** whether the missing user-global load is a bug, intended behaviour, or gated on a condition. OMP is therefore recorded as **not covered** by the shared global ruleset until a project-isolated test says otherwise. `~/.codex/AGENTS.md` itself is present and unchanged and remains the source for Codex proper.
- OMP session transcripts do not persist the system prompt (a headless run writes ~7 records: title/session/model_change/two messages/credential_pin/session_exit), so transcript grepping cannot settle this class of question — a behavioural test is required.

## Canonical

- Routine provider refresh: `omp` 18.1.21 → 18.2.1. Also captured by the same sync, unrelated to this work: `C:\` free space 22,011,707,392 → 21,743,271,936 bytes (the update's download/staging churn).
- Curated (`.local/curated-2026-09-16-omp-upgrade.ps1`): the upgrade record with hashes, the duplicate-install guard result, and the global-rules correction.
- Curated fix (`.local/fix-2026-09-16-omp-note-replace.ps1`): the stale "reads user-level global rules from `%USERPROFILE%\.codex\AGENTS.md`" sentence was **rewritten in place** rather than left beside a correction note, so the canonical record is not self-contradictory.
- The 2026-09-15 devlog's OMP row is marked RETRACTED with the reason, and a method note was added to that entry covering every row of its table.

## Gates

- `sync.ps1 -AllowDirty`: all ten providers success, validation ok (0 warnings, 0 findings).
- `tests/run-tests.ps1`: not re-run — no collector, lib, or test changes in this round (the version came from the existing provider).
- Post-upgrade smoke: `omp/18.2.1`; `omp models` resolves the provider catalog (20 `google-antigravity` models listed, including the configured `gemini-3.8-flash`); a headless turn completed normally against the configured default model.
- Self-inflicted artifacts cleaned: scratch project `E:\Dev\oprobe` removed; the temporary OMP package download used for changelog reading removed; no parked binary left in `D:\OMP`.
