# 2026-08-26 — Read-only G2 semantic review command

## Scope

Added `scripts/review.ps1` and `scripts/lib/review.ps1` to make the ignored G2 semantic draft reviewable without promoting any meaning into canonical context. The contract requires `canonical_write: false`, evidence on every suggestion/check, explicit confirmation for project and semantic suggestions, and safe absence semantics: only `verified-absent` may assert `absence_claim: true`.

The default command reports a structurally valid but confirmation-gated review. `-RequireClosed` is an explicit gate and is expected to fail while Initial Audit closure is partial or semantic suggestions remain unconfirmed.

## Verification

- `tests/run-tests.ps1`: all 20 tests passed, including valid and unsafe semantic-review fixtures.
- Current local review: 8 project suggestions, 3 semantic suggestions, and 3 unresolved checks; `canonical_write=false`; all remain confirmation-gated.
- The current FlClash candidate has no explicit `absence_claim`; the review reports a warning and treats it as not-absent rather than inferring removal.
