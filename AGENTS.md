# AGENTS.md

## Purpose

MachineContext is the private, AI-readable source of truth for this computer's environment. It exists so ChatGPT, Codex, Agy, and other agents can quickly understand the real machine before planning installation, configuration, upgrades, development, or troubleshooting.

This file contains only repository-wide agent rules. Current development goals belong in `docs/DEVELOPMENT.md`; product direction belongs in `docs/PRODUCT.md`; collection scope belongs in `docs/COLLECTION_SPEC.md`.

## Priorities

When changing MachineContext, optimize in this order:

1. maintainability;
2. fast and convenient access for local and web AI;
3. factual completeness and useful detail;
4. freshness and verifiability;
5. lightweight and simple implementation;
6. additive extensibility without large future refactors.

Do not add product complexity without a demonstrated maintenance benefit.

## Source of truth

- `CURRENT.md` is the compact AI entry point, not the canonical store.
- Canonical machine facts live under `context/`.
- `machine-context.yaml` is the stable manifest for locating canonical modules and project documents.
- If `CURRENT.md` conflicts with canonical YAML, canonical YAML wins and `CURRENT.md` must be regenerated.
- Unknown is not absent. Never convert missing evidence into `not_installed`.
- Detect objective facts locally whenever practical; do not promote old chat memory or guesses to current truth.
- Give volatile facts verification metadata and an observation time.
- Keep stable IDs stable. Prefer additive fields/modules over breaking schema changes.

## Change discipline

- Prefer small, reviewable diffs and avoid rewriting unrelated records.
- Do not duplicate full dependency manifests already owned by project repositories (`package.json`, lockfiles, `pyproject.toml`, etc.). Record references and environment-level relationships instead.
- Put machine facts in `context/machine.yaml`, software in modular files under `context/software/`, projects under `context/projects/`, cross-cutting relationships in `context/relationships.yaml`, and user installation/update conventions in `context/conventions.yaml`.
- Deterministic scripts should collect and verify facts; agents should reconcile, classify, explain, and maintain semantic context.
- Initial or recovery audits must be read-only unless the user explicitly asks for system changes.

## Privacy

The repository must remain private, but treat it as if it could leak. Never commit secrets, tokens, passwords, API keys, OAuth credentials, cookies, private keys, proxy subscription URLs/credentials, `.env` values, browser profiles, or authentication-file contents.

Prefer normalized paths such as `%USERPROFILE%`, `%APPDATA%`, and `%LOCALAPPDATA%` where practical. Collectors must use an allowlist model. Read `PRIVACY.md` before expanding collection scope.

## Before working

For repository development, read `docs/DEVELOPMENT.md` and the relevant specification. For machine-dependent planning, read `CURRENT.md` first and open canonical modules only as needed.
