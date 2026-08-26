# 2026-08-26 — Confirmation-gated curated updates

## Scope

Added `scripts/curate.ps1` and `scripts/lib/curation.ps1` for the next G2 step. The command consumes an explicit `g2-curation-confirmation` manifest, verifies evidence and stable IDs, allows only curated/conventions fields, stages and validates a proposed context, and requires `-Apply` before any canonical write.

No confirmation manifest was applied during this session. Existing observed facts and unresolved semantic questions remain unchanged.

## Verification

- Added a fixture covering project, software, and conventions proposals without writing canonical files.
- Added rejection coverage for an attempted `observed` update.
- All 22 tests pass after the command was added.
