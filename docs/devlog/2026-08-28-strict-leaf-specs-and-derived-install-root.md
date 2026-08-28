# 2026-08-28 — strict leaf specs close the last allowlist escape; OMP install root derived from the resolved executable

## Context

External re-review of `19a7ef1`/`a3e990a` accepted the four main hardening fixes but found one
remaining gap in the same privacy boundary, plus one maintainability issue:

1. `$null` allowlist entries handed values to the shared safe walker, which still recurses into
   mappings. A field expected to be a scalar (e.g. OMP `compat`, which is actually an object) was
   effectively governed by the generic walker one level below the allowlist — the same escape the
   P1 fix closed, one level deeper.
2. `Get-McAiDefinitions` hardcoded `install.root = 'D:\OMP'` for OMP. If the install moves and PATH
   is updated, the collector would keep publishing the stale root alongside a fresh executable.

## Changes

- `scripts/lib/config-projection.ps1`
  - New `scalar-leaf` allowlist spec: scalar or scalar-sequence leaves only; an unexpected nested
    mapping is rejected outright with an `unsupported-value` redaction instead of being walked
    generically.
  - `{ __items__ = ... }` namespaces now accept the strict string specs `scalar-leaf`/`scalars`
    for their values, so two-level dynamic-key maps (OCX `modelReasoningEffortMap`) no longer rely
    on an empty inner allowlist.
- `scripts/collectors/config-profiles.ps1` — every known scalar/list leaf across the OMP, DSH and
  OpenCodex allowlists moved from `$null` to `scalar-leaf` (or `scalars` for dynamic-key maps);
  OMP `compat` became a real nested allowlist (`supportsReasoningEffort` only). All conversions are
  output-identical for the current machine's configs.
- `scripts/collectors/ai-tools.ps1` — OMP `install.root` is now derived each scan from the resolved
  executable (`Split-Path`), so it tracks the real install location; `method`/`scope`/`environment`
  stay user-confirmed. Evidence is split accordingly: `install.root` attributed to `command`,
  the rest to `user-confirmed`.
- Tests: OMP fixture gains an unknown `compat` key (must be dropped and recorded in
  `unprojected_keys`) and a mapping where `contextWindow` is expected (must be rejected with an
  `unsupported-value` redaction); OCX fixture gains `modelReasoningEffortMap` with a nested mapping
  under an effort key (rejected, redacted); DSH assertions cover the effort-map and scalar `input`
  leaf shapes.
- Docs: `docs/COLLECTION_SPEC.md` section R documents the shape-declared spec vocabulary.

## Notes

- The stale `user-confirmed install` evidence entry for OMP in `context/software/ai.json` cannot be
  removed by reconciliation (evidence entries merge by exact JSON identity and only accumulate), so
  the publish step removes it once, and the following sync verifies idempotency.
- Vanilla Pi remains recorded as intentionally not installed (user decision, 2026-08); OMP is the
  Pi-lineage CLI in use.
