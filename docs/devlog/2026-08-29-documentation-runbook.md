# 2026-08-29 — documentation runbook, doc-set slimming, and a supplemental-entity fix

## Context

A full documentation audit (cold-start AI-agent perspective) found the concept layer strong but
the operations layer missing: no runbook for "machine changed → update records → sync to cloud",
no test-entrypoint reference, no gate order, and critical environment facts (push requires the
local proxy at 127.0.0.1:7988; scripts require pwsh 7+ and explicit `-RepoRoot`) existed only in
session memory, not in the repository. The doc set had also accreted: `DEVELOPMENT.md` was ~60%
frozen phase progress logs overlapping ROADMAP/devlog.

## Changes

- **New `docs/OPERATIONS.md`** — the operations contract: environment requirements, the standard
  sync flow (triggers, command table, gate order, commit/push conventions with the proxy
  prerequisite), common failure handling, an information map (category → source → canonical
  target → refresh mode), per-tool collection playbooks for the AI harness profiles (Codex shared
  config, OMP, DSH, ZCode, OpenCodex, Qoder CN, MCP) with "easy-to-miss" checklists, curated
  update flows, a new-collector checklist pointing at devlog precedents, and known limitations
  (MSIX auto-update staleness, evidence accumulation, stale semantics).
- `docs/DEVELOPMENT.md` slimmed to current phase + freeze policy + acceptance criteria; the
  Phase A–G2 build history moved verbatim to `docs/devlog/2026-08-26-v1-build-phases.md`.
- `docs/README.md` gains a task-routing table; `machine-context.json` and `AGENTS.md` register
  the runbook (AGENTS.md keeps only a pointer — it stays policy-only per its ownership rule).
- **Canonical fix found by the pre-write data audit**: `claude-desktop` still recorded MSIX
  package 1.24012.11.0; the Store app had auto-updated to 1.37937.3.0 and its versioned
  `WindowsApps` path no longer existed. Refreshed once from `Get-AppxPackage` (its
  `appx-manifest` evidence source is supplemental, not part of the routine core scan — the
  runbook now documents this staleness mode and the refresh procedure).
