# Durable Decisions

This file records decisions that should survive individual development sessions. Add or amend entries when a decision materially changes; do not use it as a chronological dev log.

## D001 — Files first, no application/database in V1

Decision: canonical state is stored as readable YAML/Markdown in Git. Local scripts perform deterministic maintenance.

Reason: the dataset is small, AI-readable files are the product's core value, Git already provides history, and a database/UI would add maintenance cost before it solves a real problem.

Status: accepted.

## D002 — Canonical YAML and generated `CURRENT.md`

Decision: `context/` is authoritative. `CURRENT.md` is a compact, generated convenience view for fast AI reading.

Reason: one canonical truth avoids drift while still allowing a highly efficient entry point for web and local agents.

Status: accepted.

## D003 — Collection by allowlist

Decision: collectors gather only explicitly useful, approved facts. They do not dump arbitrary environment variables, registries, configs, directories, or file contents.

Reason: this keeps the repository small and substantially reduces accidental secret/private-data collection.

Status: accepted.

## D004 — Detect facts, maintain semantics

Decision: objective facts such as versions, executable paths, disk free space, and command resolution should be detected locally where practical. Semantic facts such as `primary`, `legacy`, project lifecycle, and preferred install roots may be maintained by the user/agent.

Reason: scripts are better at repeatable observation; AI/user judgment is better at meaning and intent.

Status: accepted.

## D005 — Project context without dependency duplication

Decision: MachineContext records project location, repository, lifecycle, runtime/package-manager/tool/service references, important manifests, commands, endpoints, and constraints. It does not copy complete dependency graphs from project manifests/lockfiles.

Reason: project repositories already own detailed dependency truth. Duplicating it would create guaranteed synchronization problems.

Status: accepted.

## D006 — Modular software domains

Decision: software context is split by domain under `context/software/`, registered through an index. Development/AI are first; general/creative/productivity/etc. can be added later.

Reason: this permits broader personal-computing context without turning one file into a monolith or forcing a future directory rewrite.

Status: accepted.

## D007 — Git is the default history store

Decision: do not create routine timestamped inventory snapshots. Use Git commits/diffs for historical state unless a future requirement genuinely needs another history format.

Reason: duplicate snapshots add noise and storage while Git already answers what changed and when.

Status: accepted.

## D008 — Initial audit is read-only

Decision: the first audit and normal verification do not install, uninstall, move, upgrade, edit PATH, alter proxy configuration, or otherwise mutate the machine.

Reason: MachineContext observes reality; it should not silently change reality to make the inventory cleaner.

Status: accepted.

## D009 — Private repository, but no secrets

Decision: the GitHub repository remains private, yet committed data is treated as potentially exposable. Secret values are never stored.

Reason: private repository access is a useful boundary, not a substitute for correct secret handling.

Status: accepted.
