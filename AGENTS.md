# AGENTS.md

## Purpose

MachineContext is the private machine-context layer for ChatGPT, Codex, Agy, and other agents. It describes the real local environment so planning, installation, configuration, upgrading, development, and troubleshooting do not depend on repeated manual fact gathering.

The repository is a **source of truth for machine context**, not a general notes folder, package-lock mirror, project-management system, or secret store.

## Product priorities

When changing MachineContext, optimize in this order:

1. maintainability;
2. fast and convenient access for local and web AI;
3. factual completeness and useful detail;
4. freshness and verifiability;
5. lightweight, simple storage;
6. extensibility without large future refactors.

Do not add complexity merely to make the repository look more like a product. Files and small local scripts are preferred until a CLI or UI clearly reduces real maintenance cost.

## Source-of-truth rules

- `CURRENT.md` is the fast AI entry point and should stay compact.
- Canonical facts live under `context/`.
- `machine-context.yaml` is the stable manifest that points to canonical modules.
- If `CURRENT.md` conflicts with canonical YAML, canonical YAML wins and `CURRENT.md` should be regenerated.
- Unknown is not the same as absent. Never infer `not_installed` only because a tool was not found in old notes.
- Objective facts such as executable path and version should come from local detection whenever practical.
- Semantic facts such as `primary`, `legacy`, project role, or installation preference may be user/agent-maintained.
- Every volatile fact should support a verification state and observed time.
- Prefer small diffs. Avoid rewriting unrelated records during sync.

## Data model

Software records use stable IDs and may include:

- `status`: active, inactive, legacy, testing, broken, unknown;
- `role`: primary, secondary, project-only, optional;
- version and executable/install/config paths;
- installation and update method;
- verification source, command, state, and timestamp;
- relationships to tools, services, or projects.

Project records contain only environment-level context: local path, repository, status, runtime/package-manager/tool references, important manifests, services, commands, and constraints.

Do **not** duplicate complete dependency lists already owned by `package.json`, lockfiles, `pyproject.toml`, Cargo manifests, etc. Link to those manifests instead.

## Extensibility

Do not solve growth by flattening everything into one large file.

- Machine-wide facts stay in `context/machine.yaml`.
- Software is modular under `context/software/`.
- Projects are modular under `context/projects/`.
- New software domains such as `general.yaml`, `creative.yaml`, or `media.yaml` may be added later and registered in `context/software/index.yaml`.
- Cross-cutting dependencies belong in `context/relationships.yaml`.
- User conventions belong in `context/conventions.yaml`.

Prefer additive optional fields and new modules. Avoid breaking existing IDs or relocating canonical meaning unless necessary. If a breaking schema change is unavoidable, bump the schema version and provide a migration.

## Maintenance workflow

The target maintenance flow is:

`scan -> verify -> privacy check -> update canonical YAML -> render CURRENT.md -> review diff -> commit/push`

Deterministic collection should be implemented by local scripts. AI should interpret, reconcile, classify, and explain rather than invent machine facts.

During an initial audit, inspect the machine read-only first. Do not install, uninstall, move, upgrade, edit PATH, change proxy settings, or alter applications merely to make the inventory cleaner.

## Privacy and safety

The repository must remain private, but treat it as if it could someday leak.

Never commit secrets, tokens, passwords, API keys, OAuth credentials, cookies, private keys, proxy subscription URLs, `.env` values, browser profiles, or authentication-file contents.

Prefer normalized paths such as `%USERPROFILE%`, `%APPDATA%`, and `%LOCALAPPDATA%` instead of embedding the Windows account name when practical.

Collectors should use an allowlist model: collect approved facts, not arbitrary file contents.

Read `PRIVACY.md` before expanding collection scope.

## First implementation phase

Before building a GUI or database:

1. implement a read-only Windows collector;
2. populate the V1 canonical files;
3. implement verification and stale-data detection;
4. generate `CURRENT.md`;
5. implement privacy validation;
6. add a simple sync entry point;
7. test the workflow on the real machine.

A GUI is explicitly out of scope until the file/script workflow proves insufficient.
