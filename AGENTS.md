# AGENTS.md

## Purpose

MachineContext is a private, AI-readable source of truth for the local machine environment. It exists so ChatGPT, Codex, Agy, and other agents can plan installations, configuration, upgrades, development work, and troubleshooting without repeatedly asking the user to rediscover local facts.

This file contains repository-wide agent rules only. Product scope, current implementation work, collection details, and roadmap live under `docs/`.

## Read first

When working in this repository:

1. read `CURRENT.md` for the fast machine-context view;
2. read `machine-context.yaml` for canonical module locations;
3. read `docs/DEVELOPMENT.md` before implementing repository changes;
4. read `docs/COLLECTION_SPEC.md` before adding or changing machine collection;
5. read `PRIVACY.md` before expanding any data scope.

Do not rely on a chat prompt as the only source for persistent project requirements. Important requirements belong in the repository documentation.

## Repository invariants

- Canonical machine facts live under `context/`.
- `CURRENT.md` is a compact generated/convenience view; canonical YAML wins on conflict.
- Objective, volatile facts should be detected or verified locally whenever practical.
- `unknown` is not equivalent to `absent` or `not_installed`.
- Keep stable IDs stable across updates.
- Prefer additive, backward-compatible evolution over reorganizing existing data.
- Keep diffs focused; do not rewrite unrelated records during routine sync.
- Do not duplicate detailed project dependency manifests already owned by a project's `package.json`, lockfile, `pyproject.toml`, Cargo files, and similar sources of truth.
- Git history is the default history mechanism; avoid unnecessary snapshot duplication.

## Engineering principles

Optimize for, in order:

1. maintainability;
2. fast and convenient reading by local and web AI;
3. useful completeness and detail;
4. freshness and verifiability;
5. lightweight and simple operation;
6. extensibility without large future refactors.

Files plus small deterministic local scripts are preferred until a CLI or UI demonstrably reduces maintenance cost.

Deterministic collection should gather facts; AI should reconcile, classify, explain, and maintain semantic relationships rather than invent machine state.

## Safety and privacy

The repository must remain private, but treat committed content as if it could someday leak.

Never commit passwords, API keys, access/refresh tokens, cookies, private keys, proxy credentials or subscription URLs, `.env` values, authentication-file contents, browser profiles, or arbitrary personal document contents.

Collectors use an allowlist model. Record the existence or normalized path of a sensitive file only when useful; never read its secret contents for inventory purposes.

Prefer `%USERPROFILE%`, `%APPDATA%`, `%LOCALAPPDATA%`, and similar normalized paths when a literal account name adds no value.

Initial and audit-style collection must be read-only. Do not install, uninstall, move, upgrade, edit PATH, change proxy settings, or otherwise mutate the machine merely to make the inventory cleaner.

## Documentation hygiene

- Update `docs/DEVELOPMENT.md` when the active implementation phase changes.
- Update `docs/DECISIONS.md` when a durable architectural or data-model decision changes.
- Add a concise entry under `docs/devlog/` for meaningful implementation sessions or migrations.
- Update `docs/COLLECTION_SPEC.md` before a new category becomes part of normal collection.
- Keep `README.md` and `CURRENT.md` concise; detailed explanations belong in `docs/`.
