# Local maintenance scripts

V1 uses small PowerShell entry points plus domain-specific collectors.

## Entry points

- `collect.ps1` — read-only collection of approved machine facts;
- `verify.ps1` — re-check existing records and mark stale/unavailable facts;
- `render.ps1` — regenerate `CURRENT.md` from canonical context;
- `validate.ps1` — schema/reference/privacy checks;
- `sync.ps1` — orchestrate `collect -> verify -> validate/privacy -> render -> git diff`.

The entry-point files currently exist as explicit scaffolds and intentionally fail rather than pretend the workflow is implemented. The desktop/local agent should replace them during V1 development.

## Structure

- `collectors/` — small read-only Windows collectors by domain;
- `lib/` — deterministic shared helpers;
- `../tests/fixtures/` — synthetic/sanitized parser and normalization fixtures.

The authoritative collection list is `docs/COLLECTION_SPEC.md`; current implementation order and acceptance criteria are in `docs/DEVELOPMENT.md`.

Do not build a GUI, database, or always-running daemon before this workflow is reliable on the real machine.
