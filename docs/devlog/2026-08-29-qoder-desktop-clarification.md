# 2026-08-29 — qoder entity corrected to the desktop agent

## Context

The user clarified that what they installed and use is the **Qoder CN desktop
agent**; the `qoderclicn` CLI and `qodersec` helpers were pulled in by the
installer and are unknown/unused to them. The same-day earlier change had
represented qoder as the CLI (the only probeable component) — that inverted the
actual usage.

## Changes

- `scripts/collectors/ai-tools.ps1` — removed the qoder CLI definition and the
  `fallback_executable` known-location mechanism it motivated (nothing else used
  it); added a `qoder-cli-binary` path observation so the bundled CLI's presence
  stays tracked without entity status. The `.qoder-cn`/`.qodersec`/IDE install
  directory path observations remain.
- Canonical (one-time publish correction): the `qoder` entity now represents the
  desktop agent (Qoder CN 0.1.2, `D:\Qoder-CN\Qoder CN`, verified via the HKCU
  uninstall entry plus user-confirmed usage); `curated.notes` record that the
  bundled CLI/qodersec components are installed but unused. Reconciliation keeps
  entities that are no longer re-observed, so routine syncs preserve this record.
- Docs: COLLECTION_SPEC states the component-ownership rule (entities represent
  actually-used components; bundled unused components stay as path observations
  + curated notes); CHANGELOG bullet updated.
