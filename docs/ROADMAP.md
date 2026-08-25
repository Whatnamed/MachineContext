# MachineContext Roadmap

The roadmap is intentionally staged. Later phases should be pulled forward only when the previous maintenance loop is reliable.

## Phase 0 — Repository bootstrap

Status: complete.

- private GitHub repository;
- canonical context layout;
- AI entry point and root manifest;
- privacy and schema rules;
- product/development/collection documentation;
- initial script and collector folders.

## Phase 1 — Initial Audit + V1 collector

Status: next.

Goal: turn the repository from a documented skeleton into verified context for the real machine.

Deliverables:

- read-only Windows collectors for V1 scope;
- normalization to stable IDs and canonical YAML;
- verification and stale/unavailable handling;
- privacy/schema validation;
- `CURRENT.md` rendering;
- simple `sync.ps1` orchestration;
- first real-machine audit using `BOOTSTRAP_HINTS.md` only as search hints;
- initial project registry and installation conventions;
- idempotence check: a second unchanged run should produce essentially zero diff.

## Phase 2 — Maintenance hardening

Goal: make routine updates boring and dependable.

Possible work:

- targeted rescans instead of always scanning every domain;
- better error reporting without failing the whole sync;
- tests for parsers/normalizers using fixtures;
- stable formatting and ordering guarantees;
- stale-age policies per fact category where useful;
- optional reviewed commit/push helper;
- relationship consistency checks.

## Phase 3 — General software context

Goal: expand beyond development only after the core loop is trustworthy.

Add domain modules as needed, for example:

- general desktop utilities;
- creative/design/3D/video tools;
- productivity and notes/sync tools;
- browsers and other frequently discussed software.

This phase must remain selective: record software that improves future AI decisions, not every Windows package.

## Phase 4 — Convenience CLI

Goal: reduce user/agent friction without changing the canonical model.

Potential interface:

- `mc scan`
- `mc verify`
- `mc status`
- `mc sync`
- `mc project add`

The CLI should wrap the same files and validation rules rather than introduce a separate database.

## Phase 5 — Smarter planning support

Potential features:

- impact analysis before moving/upgrading a tool;
- installation-location recommendations based on real conventions and disk roles;
- update-path recommendations based on original install method;
- change summaries for web AI;
- optional scheduled verification if it proves useful.

## Optional future — Local dashboard / multi-machine

A dashboard is only justified if text + CLI becomes inconvenient for browsing or maintenance. Multi-machine support is deferred until there is an actual second long-lived machine to represent.

Any future UI should preserve the repository's readable, portable context layer rather than hide truth exclusively in an application database.
