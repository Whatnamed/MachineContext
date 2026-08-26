# Durable Decisions

This file records decisions that should survive individual development sessions. Add or amend entries when a decision materially changes; do not use it as a chronological dev log.

## D001 — Files first, no application/database in V1

Decision: canonical state is stored as readable JSON/Markdown in Git. Local scripts perform deterministic maintenance.

Reason: the dataset is small, AI-readable files are the product's core value, Git already provides history, and a database/UI would add maintenance cost before it solves a real problem.

Status: accepted.

## D002 — Canonical JSON and generated `CURRENT.md`

Decision: `context/` is authoritative structured JSON. `CURRENT.md` is a compact, generated convenience view for fast AI reading.

Reason: PowerShell 7 can read/write JSON without extra modules; JSON is easy for AI and future Rust/TypeScript tooling to consume, supports deterministic serialization/schema validation, and avoids adding a YAML parser solely for maintenance scripts.

Status: accepted. This supersedes the bootstrap-only YAML choice before any real machine data was committed.

## D003 — Collection by allowlist

Decision: collectors gather only explicitly useful, approved facts. They do not dump arbitrary environment variables, registries, configs, directories, or file contents.

Reason: this keeps the repository small and substantially reduces accidental secret/private-data collection.

Status: accepted.

## D004 — Detect facts, maintain semantics

Decision: objective facts such as versions, executable paths, disk free space, and command resolution should be detected locally where practical. Semantic facts such as `primary`, `legacy`, project lifecycle, and preferred install roots may be maintained by the user/agent. Canonical records separate `observed` and `curated` ownership so routine scans cannot erase semantic context.

Reason: scripts are better at repeatable observation; AI/user judgment is better at meaning and intent. Mixing ownership in the same flat fields creates inevitable merge/overwrite bugs.

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

## D010 — Layered discovery, not brute-force full-disk walking

Decision: discovery combines structured OS/tool sources, targeted probes, configured roots, and optional indexed broad discovery. Raw whole-disk recursive traversal is never the default fallback.

Reason: completeness comes from combining evidence sources, not reading millions of unrelated files. Brute-force walking is slow, noisy, privacy-heavy, and still cannot identify the effective/primary installation correctly.

Status: accepted.

## D011 — Discovery candidates are not canonical facts

Decision: broad filesystem/index/config hits first become local candidates/observations. They require reconciliation and appropriate verification before promotion to canonical context.

Reason: a file named `node.exe`, a stale config directory, or a copied repository does not prove a currently usable/meaningful entity.

Status: accepted.

## D012 — Stable identity with multi-source evidence

Decision: one real entity may have evidence from Registry, winget, PATH, config, package manager, and filesystem discovery. Reconciliation merges these under a stable ID. Display name or path alone is not a universal identity key.

Reason: otherwise one application appears multiple times and a simple install-path move looks like remove+add.

Status: accepted.

## D013 — Fast path, discovery path, enrichment path

Decision: V1 exposes distinct scan profiles: Quick for routine verification, Discover for broad unknown discovery, Enrich for expensive selected details, and Full for Initial Audit (`Quick + Discover + selective Enrich`).

Reason: “complete” must not mean “do every expensive operation on every sync”. This keeps routine maintenance quick without giving up broad initial/periodic coverage.

Status: accepted.

## D014 — Provider health governs absence semantics

Decision: every collector/provider reports `success`, `partial`, `unavailable`, `timed_out`, or `failed`. Missing output can only become negative evidence when the provider completed successfully and actually covers that fact.

Reason: a failed Docker/winget/runtime probe must not make MachineContext conclude that previously known software was uninstalled.

Status: accepted.

## D015 — Windows installed-app inventory uses Registry/winget, not `Win32_Product`

Decision: V1 uses Add/Remove Programs Registry data as the structured installed-app baseline and winget as package identity/update-channel enrichment. `Win32_Product` / `wmic product` is prohibited for routine inventory.

Reason: `Win32_Product` is incomplete for non-MSI software, slow, and can initiate Windows Installer consistency checks. Registry/winget are safer and more relevant to installation/update planning.

Status: accepted.

## D016 — Everything is an optional discovery accelerator

Decision: if Everything/`es.exe` already exists, Discover may use its index to find project fingerprints and portable/custom-install candidates. MachineContext never auto-installs/configures Everything and must have a bounded fallback.

Reason: its index can dramatically improve unknown discovery on multi-drive Windows machines, but product correctness must not depend on a third-party background service.

Status: accepted.

## D017 — Windows host and WSL are separate scopes

Decision: V1 records WSL presence/distros/host relationships but does not flatten Linux runtimes/tools into the Windows host inventory. Deeper WSL inventory is a future scoped-context extension.

Reason: command resolution, package managers, paths, and installed versions differ by environment. Flattening them would create misleading answers.

Status: accepted.

## D018 — Atomic publication through staging

Decision: collectors write proposed state under ignored local staging, then reconciliation/validation/privacy/rendering completes before canonical files are replaced. A failed scan must not leave partially updated context.

Reason: reliability and maintainability matter more than directly streaming probe results into Git files.

Status: accepted.

## D019 — Exact per-item check timestamps stay local by default

Decision: exact per-item/per-provider `last_checked_at` lives in `.local` state. Committed `context/status.json` holds only compact published freshness/provider-health information. Repeated scans with unchanged facts should not rewrite every entity solely to change timestamps.

Reason: this preserves freshness diagnostics without creating huge meaningless Git diffs on every run.

Status: accepted.

## D020 — No shell command strings by default

Decision: shared probe execution resolves an executable and passes an argument list, with timeout, process-tree cancellation, stdout/stderr/exit-code handling, and output caps. Shell execution is opt-in only when a probe genuinely requires shell semantics.

Reason: this avoids quoting/injection issues and makes behavior predictable across non-default paths and localized Windows environments.

Status: accepted.

## D021 — Manifest-only projects remain candidates by default

Decision: project discovery may record manifest fingerprints and package-manager evidence locally, but automatic promotion into `context/projects/` requires a verified `.git` directory/file fingerprint in V1. Non-Git projects can be promoted later through explicit verification/curated intent.

Reason: bounded roots contain SDK samples, caches, generated fixtures, and nested package directories. Treating every manifest as a long-lived project would create high-noise canonical context and silently classify temporary material as user-owned work.

Status: accepted.

## D022 — Bucket volatile free-space observations

Decision: canonical `free_bytes` storage observations are rounded down to 256 MiB buckets. Total capacity remains reported separately; exact per-check values remain local diagnostics/state when needed.

Reason: free space is useful for placement planning, but exact bytes change during the scan and create meaningless repeated-run diffs. The bucket preserves material capacity changes while keeping no-change scans byte-stable.

Status: accepted.

## D023 — Optional provider degradation stays local

Decision: optional discovery accelerators and enrichment providers retain exact `unavailable`, `timed_out`, or `failed` health in `.local` diagnostics, but do not determine the provider aggregate health of an otherwise usable audit. Required providers determine the published `provider_state`; the top-level published `state` is additionally gated by the explicit Initial Audit closure.

Reason: optional providers such as Everything or winget enrichment improve coverage but are not prerequisites for trustworthy structured observations. Their exact failures must remain visible without turning a bounded fallback or a slow external source into a whole-run failure.

Status: accepted.

## D024 — Persistent Windows host environment is separate from collector process

Decision: canonical command/path facts use the persistent Windows Machine and User environment, with Machine entries before User entries and stable de-duplication. The current collector process PATH and `Get-Command` resolution are diagnostic-only and remain under ignored `.local` state. Future WSL records use an explicit `wsl:<distro>` scope rather than being flattened into host facts.

Reason: Codex/Agy launchers and other agent runtimes may inject temporary PATH prefixes that are not installed-machine truth. Publishing those paths would make repeated audits report false primary installations and would make canonical state depend on the process that happened to run the collector.

Status: accepted.

## D025 — Dedicated verifiers and conservative verification states

Decision: high-value Windows identities use dedicated read-only verifiers instead of relying on generic command discovery. Git Bash is authoritative only when `bash.exe` is found under the verified Git-for-Windows installation root; Windows publishes both raw registry identity and a build-derived `normalized_family`; NVIDIA VRAM is authoritative only from `nvidia-smi`; Visual Studio/MSVC/Windows SDK, Codex CLI/Desktop, Supabase CLI, VS Code CLI, and .NET use their applicable native/known-root checks. The legacy AI `codex` record migrates to `codex-cli` only when a successful dedicated CLI observation exists; Codex Desktop is a separate Appx identity.

Verification state is separate from provider health. Failed, timed-out, or unavailable checks preserve prior `observed` facts and mark an existing record `unverified`. Only a successful high-confidence applicable absence check may retain the record with `present: false`, `verification: verified-absent`, and `last_known`; broad discovery and missing generic commands remain candidates or unknown.

Reason: generic PATH aliases can be WSL/App Execution Alias shims, CIM `AdapterRAM` is not a reliable NVIDIA VRAM source, and provider failure must never be mistaken for uninstall/removal. Stable identity and explicit negative-evidence rules keep routine scans trustworthy and idempotent.

Status: accepted.

## D026 — Project root policy gates automatic promotion

Decision: project fingerprint discovery assigns each candidate a bounded root policy. Automatic promotion requires a `.git` directory/file and a configured or verified project root. Developer umbrellas, SDK/tool roots, caches, generated directories, vendor paths, and unknown roots remain local candidates/evidence even when they contain Git or manifests.

Project display names use curated meaning first, then sanitized repository basename, manifest package name, and directory name. Package-manager identity prefers explicit `packageManager` or workspace metadata before lockfiles. Root policies and raw candidate evidence remain under `.local`; canonical project records store only reconciled project context.

Reason: real developer/tool roots contain SDK repositories, examples, generated output, caches, and nested packages. A Git fingerprint proves repository structure but does not by itself prove that the repository is a user-maintained environment project.

Status: accepted.

## D027 — Bounded tool fingerprints are discovery evidence only

Decision: when Discover/Full runs, fallback filesystem discovery may inspect only bounded configured/developer/tool/install roots for a small allowlist of high-value executable fingerprints. It records low-confidence candidate/evidence objects and budget diagnostics under `.local`; it never verifies or publishes a canonical software entity. Everything/`es.exe`, when already present, uses the same candidate-only semantics and query allowlist.

Reason: portable/custom installations can be missed by Registry and PATH, but arbitrary recursive file inventory is noisy, expensive, and privacy-sensitive. A filename match is useful for selecting a later verifier, not proof that the tool is usable or user-relevant.

Status: accepted.

## D028 — Strong relationships require verified observations and direct evidence

Decision: canonical relationships are derived only from `verified-present` structured observations. Installation relationships such as Git Bash -> Git, Node-local package manager -> Node, and Flutter-bundled Dart -> Flutter require matching normalized executable/install paths. Project runtime/package-manager relationships require both a verified Git project under a promotable project root and manifest fingerprint evidence. Candidate-only, non-promotable, fallback-shim, unknown, stale, or failed-provider observations remain local evidence and cannot create canonical edges.

Relationship origin remains `detected` when a dedicated provider supplies the relationship and `inferred` when a strong path rule derives it. Provider failures do not remove previous relationships; absence/removal requires a separate successful verification policy.

Reason: a relationship is useful for planning only when its endpoints and ownership are trustworthy. Strong path/evidence gates prevent broad discovery, injected runtimes, and transient provider failures from creating dangling or noisy canonical edges.

Status: accepted.

## D029 — Canonical project cleanup is explicit and staged

Decision: migration may remove a historical canonical project record only when its normalized path is classified as `sdk-root`, `tool-root`, `cache-root`, or `vendor-root` and the record has no curated intent beyond `status: unknown`. The proposed stage records the exact relative deletion path and local demotion evidence; publish deletes only those explicit paths inside the repository with backup/rollback protection. Curated records and unknown-root records are preserved.

Reason: correcting an old false-positive project must not silently erase user meaning or broaden deletion scope. Staging first makes the change reviewable, while the explicit deletion manifest keeps canonical cleanup deterministic and safe.

Status: accepted.

## D030 — Project activity evidence is local-only and non-semantic

Decision: Discover/Full may run bounded read-only Git activity probes for verified, promotion-eligible project candidates. Branch, latest commit timestamp, tracked-file dirty Boolean, and probe status remain in ignored `.local` diagnostics. The provider is optional and never writes canonical observations or infers `curated.status`, purpose, role, or active/legacy meaning.

Reason: Git activity is useful evidence for an Initial Audit review, but recency and dirty state are not reliable proof of lifecycle or user intent. Keeping the evidence local avoids canonical churn and preserves explicit semantic ownership.

Status: accepted.

## D031 — Published trust state requires provider health and audit closure

Decision: `context/status.json` exposes separate `provider_state` and `audit_closure` axes. `provider_state` is the required-provider aggregate from the current run. `audit_closure` is a compact projection of ignored `.local/audit-closure.json`, containing only its state, source, timestamp, and finding counts. Closure evidence may classify documented limitations as `accepted_unknowns`; unresolved `open_unknowns`, conflicts, or unresolved entries remain blocking. The top-level `state` is `verified` only when both axes are `verified`; missing or invalid local closure evidence or any blocking finding keeps it `partial`. Local candidate unknowns and accepted unknowns remain visible as counts but do not by themselves block closure.

Reason: a successful provider run proves that the configured checks completed; it does not prove that the documented Initial Audit has no unresolved canonical meaning. Keeping both axes makes that distinction explicit to AI readers while preserving provider failure semantics and keeping raw closure evidence out of Git.

Status: accepted.

## D032 — Listener parent and service ownership stays local-only

Decision: allowlisted local listener diagnostics may resolve a listener's process name, direct parent process name, and matching Windows service name/state/start mode. Executable path access is represented only as a Boolean and service executable identity only as a basename. PIDs, command lines, service arguments, and raw paths remain excluded; all ownership enrichment stays in ignored `.local` diagnostics and cannot promote or classify a canonical network service.

Reason: process name alone was insufficient to explain the observed FlClash listener, while raw process/service command data is noisy and privacy-sensitive. A bounded ownership label improves audit evidence without turning runtime ownership into user intent or proxy policy.

Status: accepted.
