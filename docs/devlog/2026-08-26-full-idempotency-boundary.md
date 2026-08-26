# 2026-08-26 — Full idempotency boundary

## Scope

Two consecutive Full no-publish runs were compared after the pnpm evidence change. Both runs succeeded with 293 candidates, `changed_files=[]`, and validation success. Their proposed canonical context files were byte-identical except for the expected `context/status.json` heartbeat metadata.

The ignored local diagnostics differed only in bounded discovery `visited_directories` (480 versus 469). This is a scan-local volatility signal, not a canonical fact change. The comparison therefore keeps canonical semantic idempotency separate from raw diagnostic byte identity.

## Verification

- Full runs: `20260826-102534495-34fd2444`, `20260826-102623197-8b7ddaa8`.
- Read-only audit remained `partial` with 3 open unknowns, 0 conflicts, and 1 unresolved entry.
- No curated field or canonical file was written by these runs.
