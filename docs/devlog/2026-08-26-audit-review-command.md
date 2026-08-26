# 2026-08-26 — Read-only audit closure review command

## Scope

Added `scripts/audit.ps1` and `scripts/lib/audit.ps1` as a read-only review surface for ignored `.local/audit-closure.json`. The command validates the closure document shape, duplicate entry IDs, recognized entry states, run-id mappings, unknown classification overlap, and the derived published-state projection. It does not collect machine facts, modify `.local`, update canonical JSON, or render `CURRENT.md`.

## Verification

- `tests/run-tests.ps1`: all 19 tests passed, including valid/invalid closure fixtures.
- The current local closure review is structurally valid and remains `partial`: four canonical unknowns, three open unknowns, one accepted unknown, one unresolved entry, and zero conflicts.
- `scripts/audit.ps1 -RequireVerified` remains an intentional failing gate until the documented G1 semantic questions are reviewed; the default command is useful during the review period because it reports a valid partial closure without treating it as complete.
