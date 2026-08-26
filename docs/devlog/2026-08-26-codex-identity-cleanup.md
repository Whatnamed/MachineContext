# Codex identity cleanup

- Removed the obsolete generic AI collector lookup for the legacy `codex` entity. `codex-cli` and `codex-desktop` remain owned by the dedicated host verifier.
- Added a reconciliation fixture proving that a legacy `codex` record migrates to `codex-cli` while retaining safe observed evidence and curated intent.
- This change only updates repository code/tests; no machine state was modified and no curation manifest was applied.
