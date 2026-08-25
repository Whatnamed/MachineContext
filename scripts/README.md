# Local maintenance scripts

V1 uses small Windows-first PowerShell entry points plus source-specific collectors and shared reconciliation helpers.

## Entry points

- `collect.ps1` — read-only provider/discovery execution, supporting scan mode/scope;
- `verify.ps1` — targeted re-verification of known entities/providers;
- `render.ps1` — deterministic regeneration of `CURRENT.md` from canonical JSON;
- `validate.ps1` — JSON/reference/privacy/invariant checks;
- `sync.ps1` — staging -> collect/discover -> reconcile/verify -> validate/privacy -> render -> atomic publish -> git diff.

The entry-point files currently exist as explicit scaffolds and intentionally fail rather than pretend the workflow is implemented. V1 development should replace them with real behavior.

## Scan modes

- `Quick` — routine structured verification;
- `Discover` — broad candidate discovery;
- `Enrich` — selected expensive detail;
- `Full` — Initial Audit (`Quick + Discover + selective Enrich`).

Exact CLI parameter names may evolve, but these behavioral modes are a V1 architecture requirement.

## Structure

- `collectors/` — small read-only providers by source/domain;
- `lib/` — probe execution, JSON, path normalization/redaction, identity/reconciliation, staging, privacy, diagnostics;
- `../tests/fixtures/` — synthetic/sanitized parser/reconciliation fixtures;
- `../.local/` — ignored staging/raw candidates/local check-state/diagnostics.

Read:

- `docs/COLLECTION_SPEC.md` for **what** information is valuable;
- `docs/DISCOVERY_DESIGN.md` for **how** candidates are found/reconciled;
- `docs/IMPLEMENTATION_GUIDE.md` for subprocess, ownership, Windows inventory, Git and test constraints;
- `docs/DEVELOPMENT.md` for implementation order.

Do not build a GUI, database, MCP server, cross-platform abstraction, or always-running daemon before this workflow is reliable on the real machine.
