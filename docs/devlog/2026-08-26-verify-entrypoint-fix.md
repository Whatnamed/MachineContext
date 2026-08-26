# 2026-08-26 — Verification entrypoint null-filter fix

## Finding

Running `scripts/verify.ps1 -Mode Quick` without `-Provider` failed under PowerShell 7 StrictMode because the null provider parameter was accessed through `.Count`.

## Fix

The entrypoint now computes an explicit Boolean provider-filter guard before selecting diagnostics. A regression test invokes the real Quick verification entrypoint without a provider filter and checks its JSON run id, provider list, and read-only note.

No canonical files were written. The successful verification run was `20260826-110256644-5d4e740e` with overall health `success`.

## Verification

- All 24 tests pass.
- The direct Quick verification command exits successfully.
- `verify.ps1` continues to report that canonical context was not modified.
