# Published status audit gate

## What changed

The published status now keeps provider execution health separate from Initial Audit closure:

- `provider_state` remains the required-provider aggregate for the current run;
- `audit_closure` is a compact projection of ignored `.local/audit-closure.json`;
- top-level `state` is `verified` only when both are `verified`;
- missing or invalid closure evidence, conflicts, canonical unknowns, and unresolved entries keep the top-level state `partial`;
- local candidate unknowns are counted but do not independently block closure.

`CURRENT.md` renders all three states and the compact finding counts. No raw closure text or additional machine data is published.

## Evidence

The current closure evidence remains `partial`: five canonical unknown categories are recorded, with no conflicts. The provider aggregate is `verified`, so the generated status is intentionally `state=partial`, `provider_state=verified`, `audit_closure.state=partial`.

The projection is covered by the PowerShell test fixture for partial findings, verified closure, candidate-only unknowns, and the two-gate published state transition.
