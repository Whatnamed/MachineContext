# Config projection privacy-boundary hardening

## Scope

Post-review security/correctness patch for `context/configs/`. Data results and module design were accepted; the review found the implementation's privacy guarantee was weaker than documented. Four fixes, no architecture changes:

1. **Per-field allowlists**: OMP/DSH/OpenCodex projectors now project provider/model objects through `ConvertTo-McAllowlistedProjection` with explicit per-tool field tables; unknown fields are dropped by default and recorded by name/path only in `projection.unprojected_keys`. The shared generic sanitizer (`ConvertTo-McSafeProjectionValue`) remains as defense in depth on every surviving leaf value. ZCode already used explicit field picking and is unchanged apart from the fallback fix below.
2. **MCP split-argument leak**: MCP args are now filtered as a sequence (`Get-McSafeMcpArguments`); credential flags (`--token`, `--api-key`, `-H`/`--header`, ...) are dropped together with the argv they consume, closing the `["--token", "<value>"]` window that per-argument checks missed.
3. **Freshness**: collection now distinguishes *parser/provider failed* (previous record kept untouched) from *source confirmed absent* (`profile_states: source-missing`); reconciliation marks such last-known profiles `observed.source_state: stale` with a static reason, and `index.json` plus CURRENT.md surface the state.
4. **ZCode fallback removed**: the userprofile `config.json` (known stale sensitive copy) is never parsed or promoted; it stays a path/exists record. If the active appdata config disappears, the profile is stale — never "current" from the old copy.

Incidental fidelity fix found during the work: OpenCodex `disabledModels` was published as a string because `Get-McCollectionProperty` enumerates single-element arrays; the projector now reads properties through entry-based walking, so array shapes survive.

Also landed while touching the module: OMP `observed.install` (root/method/scope/environment, user-confirmed provenance) in `software/ai.json`; the hardcoded `pi` entry was removed from the MCP `unresolved` list and replaced by a curated note (vanilla Pi intentionally not installed; OMP is the Pi-lineage CLI in use).

## Verification

- New fixtures: unknown `headers` blocks under OMP/DSH/OpenCodex providers (innocent names, opaque values) must be dropped and listed in `unprojected_keys`; split-form MCP credential pairs must vanish; single-entry model lists must stay arrays; ZCode with missing active config must return no profile; stale marking must be byte-idempotent and index-visible; validator accepts `source_state: current|stale` and rejects other values.
- Full suite passes; live smoke projection validates clean for all four tools with zero credential values in output.
