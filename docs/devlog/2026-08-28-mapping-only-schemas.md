# 2026-08-28 — nested-object schemas are now mapping-only

## Context

Follow-up review of `9b9a224` confirmed the strict leaf specs but found the mirror
image of the same hole: a field declared as a nested object (IDictionary allowlist)
whose value degrades into a bare scalar was still published through the shared safe
walker, and a scalar item smuggled into a sequence-of-mappings was published the
same way. Expected-object → actual-scalar was accepted while expected-scalar →
actual-object was already rejected.

## Changes

- `scripts/lib/config-projection.ps1` — under an IDictionary allowlist the walker
  now enforces mapping-only schemas: a bare scalar value is rejected with an
  `unsupported-value` redaction, and a sequence is accepted item-by-item with every
  item required to be a mapping (scalar items are redacted, normal model objects
  keep projecting).
- `scripts/collectors/config-profiles.ps1` — two allowlists relied on the old
  permissive behavior and were re-specced to equivalent strict forms:
  - OMP config `providers` (dynamic keys whose values are scalar sequences, e.g.
    `webSearchOrder`) moved from `{ __items__ = { webSearchOrder } }` to `scalars`;
  - DSH `agent-presets` (names → scalar roles) moved from an empty-allowlist
    `__items__` to a direct strict scalar-collection projection.
- Tests/fixtures: an OMP fixture model now carries `compat: opaque-secret-value`
  (string where a nested object is declared — the whole field is rejected and
  redacted) and the leaky provider's model list carries a stray scalar item
  (rejected and redacted while the real model object survives).
- Docs: `docs/COLLECTION_SPEC.md` states the mapping-only rule; CHANGELOG bullet
  extended.

Both re-specced allowlists are output-identical for the current machine's configs,
so the canonical config profiles stay byte-identical.
