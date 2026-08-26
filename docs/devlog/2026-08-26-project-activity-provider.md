# 2026-08-26 — local project activity provider

Added the optional `project-activity-local` provider for Discover/Full runs. It examines only verified, promotion-eligible Git project candidates through the shared safe probe and records branch, latest commit timestamp, tracked-file dirty state, and per-probe status under ignored `.local` diagnostics.

The provider returns no canonical value. It does not retain commit messages, raw `git status`, file lists, diffs, source, or dependency contents. Missing repositories and probe failures remain `unverified`/unknown and degrade only this optional provider; they never change project lifecycle or curated meaning.

Verification:

- `tests/run-tests.ps1`: all 19 test cases passed, including missing-repository failure semantics.
- Full publication `20260826-084308690-fef1c1ba`: validation passed; eight project activity records were verified.
- Full repeat `20260826-084429235-3d6ca748`: 19 proposal targets matched current canonical files byte-for-byte; project activity diagnostics were equal.
- Quick repeats `20260826-084543944-61ab1a02` and `20260826-084608430-62fd3b50`: nonvolatile canonical context had zero differences; only expected status/CURRENT verification metadata changed.
