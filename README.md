# MachineContext

MachineContext is a private, AI-readable source of truth for this computer's environment.

Its purpose is to let ChatGPT, Codex, Agy, and other agents quickly understand the machine before planning installations, development work, configuration changes, upgrades, or troubleshooting.

## Design goals

MachineContext should remain:

- maintainable: objective facts should be re-detectable instead of manually copied forever;
- fast to read: start from `CURRENT.md`, then open only the relevant canonical files;
- complete enough for decisions: versions, paths, install/update methods, roles, constraints, projects, and important relationships;
- current: detected facts carry verification state and time;
- lightweight: do not mirror package-lock files, installed-app databases, logs, caches, or secrets;
- extensible: new software domains and projects should be addable without reorganizing the repository.

## Read order

For an AI planning a machine-dependent task:

1. Read `CURRENT.md`.
2. Read `machine-context.yaml` to locate canonical sources.
3. Open only the relevant files under `context/`.
4. For a specific development project, read its MachineContext project record and then the project's own repository manifests if deeper dependency detail is required.

`CURRENT.md` is a convenience view. Canonical YAML files under `context/` win if there is a conflict.

## V1 scope

The first version focuses on:

- OS, hardware, storage, shells, paths, and environment;
- development runtimes and package managers;
- SDKs, compilers, CLIs, cloud tools, AI coding tools, and local services;
- network/proxy facts relevant to development;
- active local projects and their environment-level dependencies;
- installation, location, and update conventions;
- cross-tool and project relationships;
- privacy-safe collection and verification.

General non-development software can be added later as additional software modules without changing the core model.

## Repository visibility

This repository is intended to remain **private**. It still must never contain secrets. See `PRIVACY.md`.
