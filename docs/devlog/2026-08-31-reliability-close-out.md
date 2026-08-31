# 2026-08-31 — Long-term reliability close-out

Scope: fix the small set of already-identified reliability issues that genuinely affect MachineContext as a long-term machine source of truth, then stop. V1 stays feature-frozen; no deferred item beyond the list below was touched.

## What changed

1. **Canonical validation coverage (P1).** `Get-McCanonicalFiles` (staging.ps1) now returns every JSON file under `context/` (except `_template.json`) by recursive scan instead of manifest entries plus per-directory exceptions. Software modules (`development.json`, `ai.json`, `creative.json`, `productivity.json`, and any future module) previously never entered the validator at all — the software-contract branch in validation.ps1 was dead code for them. Generic invariants (deterministic JSON, privacy sweep, literal user-path guard, .NET metadata) and the software record contract now apply automatically to any future module. Added forward index-reference validation: software/configs index module paths must exist (`broken_software_index_reference` / `broken_config_index_reference`), and the project index `id` must match the referenced record (`project_id_mismatch`).
2. **Serializer emits the repository form (prerequisite for CI).** `ConvertTo-Json` separates lines with the platform newline; on Windows that meant canonical files were CRLF in the working tree and only became LF through git normalization. `ConvertTo-McJsonText` now normalizes the whole document to LF (matching `.gitattributes` `eol=lf`), so `validate.ps1` is byte-exact on any checkout, including CI.
3. **ai-tooling provider failure parity (P1/P2).** The provider failure map was missing `omp`, `opencodex`, `grok`; a whole-provider failure left them verified-present. Map now matches `Get-McAiDefinitions`, and a parity test fails the suite if a future AI tool is added without updating the map. Semantics unchanged: provider failure → `unverified`, canonical record retained, never interpreted as absent.
4. **Codex CLI known-path fallback (P2).** `Invoke-McHostCommandVerifier` gained `-KnownPathsAreHints`; the Codex CLI verifier uses it, so when persistent PATH resolution finds nothing, the historical `E:\Codex\codex-cli\codex.cmd` is recorded as a low-confidence candidate hint (`known_install_path_present`) instead of being probed into a verified-present authoritative entity. Other verifiers (VS Code App Paths, dotnet vendor paths) keep their authoritative known-path semantics. On this machine PATH resolves codex to the same path, so no canonical change.
5. **Test runner PASS/FAIL (P2).** `Invoke-McTest` decides PASS/FAIL by failure-count delta instead of a message-prefix heuristic that printed PASS after assertion failures. A `-SelfTest` mode runs a synthetic suite (pass/failed assertion/throwing block); the main suite asserts the runner prints FAIL for both failing blocks and never PASS.
6. **Minimal Windows CI (P2).** `.github/workflows/repository-contract.yml`: `windows-latest`, runs `tests/run-tests.ps1` and `scripts/validate.ps1` on push/PR with paths filters. It does not collect, sync, verify the runner as the user's machine, publish, or commit.

## Documentation consistency

- `docs/ARCHITECTURE.md`: canonical context list was missing `context/configs/`.
- `docs/COLLECTION_SPEC.md`: project lifecycle status drift (`legacy`/`throwaway` are software/exceptional vocabulary, not the accepted lifecycle set `active/paused/maintenance/archived/experimental`).
- `docs/DISCOVERY_DESIGN.md`: Quick no longer reads as doing broad Registry uninstall enumeration (that is Discover/Full only).
- `scripts/README.md`: Enrich stated honestly as a reserved mode without a standalone general pipeline.
- `README.md`: DEVELOPMENT.md described as the feature-frozen normal-use phase, not "active implementation".

## Verification

- Full test suite PASS (assertion-level runner included); self-test regression proves failing blocks print FAIL.
- `validate.ps1`: ok, 0 errors, 0 warnings over all canonical files including the newly covered software modules.
- Two consecutive Quick syncs: idempotent, only the `verified_at` heartbeat; canonical content diff limited to the heartbeat and live free-storage bytes. Software/project/network/conventions/machine-path/curated data byte-stable.
- Privacy sweep on the diff: no credential-shaped values, no literal user-profile paths.

## Deliberately not done

- `audit_closure` counts left as-is (`state: partial` still reflects the real local audit evidence; provider freshness and audit closure remain separate projections).
- Deferred items from the 2026-08-30 review (machine-specific roots → conventions.json, dsh `agent_presets` naming, ai.json domain scope, doc language policy, spec TOC/DECISIONS sort) remain deferred.
