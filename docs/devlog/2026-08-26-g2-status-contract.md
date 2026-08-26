# G2 project status contract

## Scope

The G2 curation validator now distinguishes project lifecycle statuses from software/AI operational statuses. Project patches follow `context/projects/index.json.project_policy.statuses` plus `unknown`; software patches retain the generic curated status set.

This resolves the mismatch where the project policy documented `paused`, `maintenance`, `archived`, and `experimental` but the curation validator used only the software enum. No curated value was written by this change.

## Verification

Regression coverage accepts `paused` for a project proposal, rejects it for a software proposal, and keeps the existing dry-run/observed-ownership checks intact.
