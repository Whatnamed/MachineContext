# Devlog — 2026-10-05 reconcile correctness: stale failure verification metadata

Same-day follow-up to `2026-10-05-cli-tool-maintenance.md`. Scope: one canonical
correctness defect and nothing else — no CLI upgrades, no Flutter repair, no other tool
maintenance.

## Symptom

Canonical carried contradictory states: `verification: verified-present` alongside
`verification_reason: timed_out` / `failed` with `verification_provider` — on
`opencodex` and `dart` / `git-lfs` / `pip` (`timed_out`) and `flutter` (`failed`) at
commit `2474107`.

## Root cause (confirmed in code, not assumed)

- Failure path: probe/provider failures become verification events; `Set-McObservedVerification`
  (reconcile.ps1) writes `verification=unverified` plus `verification_provider` /
  `verification_reason` into `observed`.
- Success path: a fresh successful observation normally carries **neither** metadata
  field (runtimes/ai probe observations emit `verification: verified-present` only).
  `New-McObservedEntityRecord` → `Merge-McObservedObject` merges last-known-value style:
  fields present only in the previous `observed` are retained. The failure metadata from
  an earlier degraded round therefore survived the success transition, producing
  `verified-present` + stale failure reason.
- Host verifiers are the legitimate exception: their success observations supply their
  own `verification_provider`/`verification_reason` pair (`success`,
  `version-probe-success`, `vswhere-installation-found`), which the merge overwrites
  correctly. The 2026-10-05 round's diff hid these stale fields in plain sight because
  they looked exactly like that legitimate pattern.

## Fix (minimal, reconcile-side)

`New-McObservedEntityRecord` (reconcile.ps1): after the observed merge, if the resulting
`verification` is `verified-present`, drop `verification_reason` /
`verification_provider` unless the **current observation itself supplies them**. This
keeps every legitimate success-reason pair, keeps fail-soft / last-known-value semantics
untouched (a failed probe still produces no entity observation, retains the last-known
version/path, and the event still writes `unverified` + its reason), and also cleans an
already-contradictory record on its next successful verification. The fix lives in
reconcile rather than in observation provenance because the metadata is written and
meaningful by the event path (`Set-McObservedVerification`), and only the
observation-merge transition loses its association.

`sync.ps1` also gained a one-line `#Requires -Version 7` fail-fast guard, matching the
OPERATIONS runbook requirement and preventing a repeat of the 5.1 degraded publish from
this same day.

## Tests

New regression block `stale failure verification metadata must not survive a later
success` (tests/run-tests.ps1), covering:

1. `verified-present` → `unverified/timed_out`: provider/reason recorded, last-known
   version/executable/present preserved;
2. `unverified/timed_out` → `verified-present`: stale provider/reason dropped, current
   version applied;
3. an already-contradictory record (`verified-present` + `failed`) is cleaned by the
   next success;
4. a genuinely still-failing entity stays `unverified` with its actual reason and
   last-known version;
5. host-verifier-style successes that supply their own provider/reason keep them.

Full suite: 58 blocks, all PASS (pwsh 7).

## Canonical outcome (published by sync, not hand-edited)

- `opencodex`, `dart`, `git-lfs`, `pip`: stale `verification_provider` /
  `verification_reason` removed; clean `verified-present`.
- `flutter`: the probe is intermittently unhealthy (flips between the 8s probe budget
  `timed_out` and the pipe-busy `failed`); the latest sync recorded
  `unverified` / `failed` with last-known version `3.41.9`, executable,
  command_resolution and install root retained — the honest fail-soft state.
- `pnpm` (`persistent-command-not-found`) and every `verified-present` + success-reason
  pair unchanged — genuinely correct records.

## Gates

- `tests/run-tests.ps1` (pwsh 7): 58/58 PASS, including the new block.
- `sync.ps1` (pwsh 7): success, validation ok.
- `validate.ps1` (pwsh 7): `ok: true`, 0 errors / warnings / findings.
- Idempotency: consecutive syncs now differ only in the heartbeat, genuine storage
  free-space drift, and pre-existing probe-timing variance (flutter's failure mode
  `timed_out` ↔ `failed`, and npm's `install.cache` field appearing when
  `npm config get cache` completes within the 8s probe budget). No entity-level
  verification flip is attributable to the fix; the variance existed before it (it is
  where the original stale metadata came from).
