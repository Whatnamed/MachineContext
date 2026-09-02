# 2026-09-02 — correctness/fidelity close-out (CI, FreeFileSync, Git version, Grok duplicate)

## 1. repository-contract CI made hermetic

Run 33638920478 failed on a clean runner: the curation-confirmation test ran against the
real repo root and implicitly required the developer's `.local/g2-semantic-review.json`
(production curation contract), which a GitHub runner does not have. The block now builds a
throwaway fixture repository (minimal `context/projects`, `context/software`,
`context/conventions`, plus its own `.local/g2-semantic-review.json`) and runs every
`New-McCurationPlan` against that root; the real review draft is hash-checked in `finally`
to prove the test never rewrites developer state. The workflow's validation step runs with
`if: ${{ !cancelled() }}` so unit failures cannot hide validation findings, and
`actions/checkout` moved v4 → v7.0.1 (Node 20 deprecation).

## 2. FreeFileSync correction: 14.5 → 14.11 in place

The previous round's claim that the free edition "cannot be updated in place" was wrong:
only **silent** installation (`/silent`, `/DIR`) is Business-edition-gated. The official
**interactive** 14.11 installer recognized the registered `E:\FreeFileSync` root and updated
in place (config, GlobalSettings, and the Obsidian sync jobs intact; no second install).
The supplemental productivity entity was refreshed to 14.11 with a registry evidence entry,
and the real constraint — "in-place updates need the interactive installer; silent /dir is
Business-only" — is now curated semantics on the entity. The upgrade-round devlog was
corrected accordingly.

## 3. Git for Windows exact version fidelity

`git version 2.55.0.windows.5` was reduced to `2.55.0` by the generic semantic-version
parser, so a `.windows.N` package-only update would have been invisible. The
git-for-windows collector now parses the vendor suffix itself and records additive
`observed.distribution_version` (`2.55.0.windows.5`) next to the unchanged upstream
`version` (`2.55.0`); the generic parser is untouched. The renderer prefers
`distribution_version` when present, so CURRENT.md shows the exact package version. The
evidence fields list grew accordingly (the stale pre-change evidence entry was removed once
via a one-time script, since evidence is append-only). SCHEMA.md and COLLECTION_SPEC.md
document the field.

## 4. Grok stale duplicate moved to observed

The off-PATH `%USERPROFILE%\.grok\bin\grok.exe` 0.2.112 copy was previously described only
in `curated.notes`. The ai-tooling collector now probes declared vendor-default alternative
locations (existence + fail-soft version probe) and publishes them as
`observed.alternative_installations` with their own evidence; curated keeps only the
operational semantics (custom layout, official install.ps1 + GROK_BIN_DIR update method).

## Drift picked up in the same sync

- Codex Desktop auto-updated 26.825.6671.0 → 26.831.2377.0 (entity + versioned WindowsApps
  path + mcp.json `cua_repl`/`node_repl` runtime paths).
- Verification heartbeat and storage free-space drift.

## Gates

Full test suite PASS (including the three new blocks), validate 0 findings, two consecutive
syncs converge (heartbeat only), privacy sweep clean.
