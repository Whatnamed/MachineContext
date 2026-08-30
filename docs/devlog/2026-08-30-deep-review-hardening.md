# 2026-08-30 — Deep-review hardening pass

A three-track deep review (code, doc consistency, data/tests) surfaced findings that this session fixed in chunked commits. Every fix was root-caused first; verification was tests + `sync.ps1` twice + `validate.ps1` with zero findings.

## Crash-grade bugs on failure paths (the fail-soft architecture's own blind spot)

- `hardware-verifiers.ps1` returned `-Health $failureHealth` without defining it (copy from the visual-studio reference lost the assignment), so an nvidia-smi probe timeout threw under StrictMode and discarded the promotion candidate. Restored the reference semantics (`timed_out` → `timed_out`, else `partial`) with a probe-timeout test.
- `Get-McProviderFailureEvents` indexed its hard-coded provider→entity map with any failed provider name; unmapped providers (nvidia-smi, config-profiles, project-activity-local, ...) produced a null deref that aborted the whole sync. Unmapped providers now contribute no entity-level events, with a mapped+unmapped fixture test.
- `docs/OPERATIONS.md` documented `curate.ps1` as generating a manifest, but `ConfirmationPath` is mandatory and the script consumes one; no example existed anywhere. Fixed the row, added `docs/examples/curate-confirmation.example.json` (validated against the real manifest validator with a synthetic review draft).

## Reconciliation hardening

- Lowercase-id guards used case-insensitive `-match`; switched to `-cmatch`/`-cnotmatch` (4 sites) with negative assertions.
- Five empty catch blocks around canonical reads silently overwrote curated intent on a corrupt file; reads now go through `Read-McCanonicalJsonOrThrow` (abort, matching the validation failure policy), plus an integration test proving a corrupt profile aborts without being overwritten.
- Seven drifted null-safe property getter copies consolidated: the canonical trio moved to `json.ps1` (loaded first by every entry point); collection/relationships/system/rendering variants now delegate (canonical getter gained `-Default`); audit (array-preserving output) and validation (present-null semantics) stay separate, now documented. `Get-McContractProperty`'s `-ceq` key comparison relaxed to `-ieq`, so the sensitive-key denylist catches case variants.

## Documentation propagation (D036–D039 outcomes)

- CHANGELOG phase line updated to feature-frozen reality; SCHEMA.md/COLLECTION_SPEC.md status enums aligned with the curation contract (drop `compatibility-only`); PRIVACY.md rule 2 now allows the D039 `credential_configured: true` form; OPERATIONS info map says five MCP sources; README layout lists audit/review/curate; ARCHITECTURE/IMPLEMENTATION_GUIDE curated examples updated to the D038 no-value-omission shape; D038 example fixed.

## Data and derivation

- New derivation rule: `uvx provided_by uv` (same installer-root bundling evidence as dart→flutter).
- One-off corrections (lib-based script in `.local/`): codex-cli `config_paths` → `config.toml` (live-verified); morpho root_policy evidence completed to `canonical-project/canonical-project-index`; network/relationships `meta.state` → `observed`.
- Snipaste version/path mismatch was a false alarm: the exe's FileVersion is genuinely 2.11.3 while the folder name says 2.10.8.
- Real drift published: qoder `mcp-router.json` no longer exists on disk.

## New coverage

- Validator negative paths (privacy sweep, literal user path, broken project reference) and a render byte-determinism test.
- The literal-path test immediately caught a real validator bug: the check ran on raw JSON text where backslashes are escaped, so it could never match a serialized Windows path; it now walks decoded values.

## Deliberately deferred

- Machine-specific roots hardcoded in collectors (projects.ps1, ai-tools.ps1, network port allowlist, ZCode default path duplicated twice) should move to `conventions.json`'s known_roots mechanism — a separate, reviewable change.
- `status.json` audit_closure counts cite uncommitted `.local/audit-closure.json` (not reproducible from the repo); needs a provenance decision.
- dsh profile key-naming inconsistency (`agent_presets` vs `agent-presets`) is collector projection shape; ai.json domain scope drift (desktop chat/design apps) is a reorganization the invariants say to avoid casually.
- Doc language split (English contracts vs Chinese runbooks) remains an unratified policy question.
