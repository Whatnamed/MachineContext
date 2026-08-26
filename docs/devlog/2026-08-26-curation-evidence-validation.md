# 2026-08-26 — Curation evidence and timestamp validation

## Finding

The confirmation contract required non-empty evidence references, but non-empty strings alone did not prove that the evidence came from the declared G2 review. PowerShell JSON parsing also materializes UTC ISO timestamps as `DateTime` values.

## Fix

`scripts/lib/curation.ps1` now accepts valid UTC values materialized by `ConvertFrom-Json`, rejects invalid timestamp shapes, and requires every `evidence_refs` value to be either the declared review path or an exact string present in that review. Empty evidence sequences are rejected.

The fixture covers valid evidence, review-external evidence, valid/invalid timestamps, and the existing curated-only/empty-manifest gates. No confirmation manifest was applied.
