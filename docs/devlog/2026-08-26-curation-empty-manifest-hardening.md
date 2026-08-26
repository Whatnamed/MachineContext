# 2026-08-26 — Empty curation manifest hardening

## Finding

PowerShell can expose an omitted JSON sequence as null. The G2 confirmation validator therefore needed explicit null-safe counts; otherwise a manifest with no project, software, or conventions update could be mistaken for a non-empty confirmation.

## Fix

Confirmation validation now treats omitted update sequences as zero and rejects an otherwise confirmed-but-empty manifest with `curation_empty`. The fixture covers the rejection while preserving the existing software-only confirmation case.

No canonical data was changed or applied.
