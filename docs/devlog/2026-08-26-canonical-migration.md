# 2026-08-26 — Staged canonical migration

- Added a conservative migration gate for historical project records. Records under `sdk-root`, `tool-root`, `cache-root`, or `vendor-root` are demoted only when their curated section contains no intent beyond `status: unknown`.
- Proposed runs record demoted project evidence in `.local` and carry an explicit repository-relative deletion list. Publish deletes only those listed staged files with backup/rollback handling.
- Curated records and unknown-root records remain preserved; relationships referring to a demoted project are removed from the proposed relationship set to avoid dangling canonical references.
