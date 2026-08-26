# MachineContext Architecture

## Architecture summary

MachineContext uses a files-first architecture with six responsibilities that must stay distinct:

1. **Discovery** — find possible tools/projects/installations from structured sources and bounded/indexed search.
2. **Verification + reconciliation** — turn candidates/evidence into stable entities and resolve multi-source conflicts.
3. **Canonical context** — current machine facts and curated semantics under `context/` as JSON.
4. **AI entry view** — `CURRENT.md`, a short generated summary for fast consumption.
5. **Maintenance tooling** — local deterministic PowerShell under `scripts/`.
6. **Project documentation** — `docs/`, which describes MachineContext itself rather than the user's machine.

Git provides history; private GitHub provides cross-session/cross-agent sharing to web ChatGPT and local agents.

## Source-of-truth boundaries

### Root manifest

`machine-context.json` is the stable manifest. Consumers should discover canonical paths from it instead of hard-coding every future module.

### Canonical context

`context/` owns publishable current context:

- `status.json` — compact publication freshness and provider-health summary;
- `machine.json` — OS, hardware, storage, shells, important paths, environment constraints;
- `network.json` — proxy/network context and approved local services;
- `conventions.json` — installation, location, and update conventions;
- `relationships.json` — useful cross-tool/project relationships;
- `software/` — modular software domains;
- `projects/` — environment-level records for long-lived local projects.

Canonical records distinguish collector-owned `observed` fields from user/agent-owned `curated` semantics where both coexist.

### Local non-publishable state

`.local/` is ignored by Git and may contain:

- raw/candidate discovery results;
- exact per-provider `last_checked_at` timestamps;
- staging files;
- temporary winget/Everything outputs;
- local diagnostics/cache.

Nothing in `.local/` is automatically safe to commit.

### Generated view

`CURRENT.md` is optimized for reading speed. It must contain a generated marker and should be rendered from canonical context rather than manually maintained as a second truth store.

### External project truth

Detailed project dependencies remain in each project's own repository manifests and lockfiles. MachineContext stores enough project context to locate and reason about those sources, not a duplicate dependency database.

## Data flow

```text
real Windows machine
      |
      +-------------------------+
      |                         |
      v                         v
structured providers       discovery providers
Registry/CIM/winget/CLI    roots/manifest/Everything
      |                         |
      +-----------+-------------+
                  v
          local observations/candidates
                  |
                  v
        identity + evidence reconciliation
                  |
                  v
          targeted verification
                  |
                  +----> provider health / conflicts
                  v
           detected observations
                  |
                  +----> preserve curated semantics
                  v
        proposed canonical JSON in staging
                  |
          validate/privacy/references
                  |
                  +----> render CURRENT.md
                  v
             atomic replace
                  |
                  v
        git diff -> review -> commit/push
                  |
                  v
          private GitHub repository
          /                       \
 web ChatGPT reads CURRENT     local agents read JSON/live machine
```

## Why discovery and collection are separate concepts

`COLLECTION_SPEC.md` defines **what information is valuable**. `DISCOVERY_DESIGN.md` defines **how to find it when nobody remembers what is installed**.

A checklist-only collector has poor recall. A brute-force disk crawler has poor speed, privacy, and precision. MachineContext combines structured system sources, targeted verifier commands, bounded root search, and optional Everything index discovery.

Discovery result != truth. A path/config/filename hit is only candidate evidence until reconciliation/verifier confirms it.

## Entity model and ownership

A typical software entity conceptually has:

```json
{
  "id": "node",
  "kind": "runtime",
  "observed": {
    "present": true,
    "version": "...",
    "executable": "...",
    "install": {},
    "evidence": []
  },
  "curated": {
    "status": "active",
    "role": "primary",
    "purpose": null,
    "constraints": []
  }
}
```

The exact schema may evolve additively, but the ownership boundary is durable:

- collector/reconciler may update `observed`;
- routine sync must preserve `curated`;
- AI/user may modify `curated` based on real observed evidence;
- inferred semantic values should not masquerade as detected values.

## Identity and evidence

One software installation may be discovered through Registry, winget, PATH, executable probing, config files, and filesystem indexing. These should normally converge into one entity with several evidence records.

Stable identity prefers vendor/package/canonical IDs over display names or paths. A path move should not automatically become “old software removed + new software added”.

Field source precedence is field-specific rather than global. Example: executable version is best verified by the resolved executable; install/update ownership is better established by package-manager/installer metadata.

Conflicting high-quality evidence produces diagnostics rather than silent overwrite.

## Scan profiles

- **Quick** — routine verification of known state and cheap structured providers.
- **Discover** — broad candidate discovery for Initial Audit/large environment changes.
- **Enrich** — expensive selected details, kept off the normal scan path.
- **Full** — Initial Audit combination of Quick + Discover + necessary selective Enrich.

This is essential to satisfy both completeness and fast maintenance.

## Collector/provider design

Collectors/providers are small, source-specific, read-only, and fail-soft.

Each provider returns observations plus health:

`success | partial | unavailable | timed_out | failed`

A missing executable, permission failure, non-default path, unavailable daemon, or optional adapter absence is normal input, not a fatal whole-scan condition.

Shared subprocess infrastructure provides executable resolution, argument-list execution, timeout, process-tree cancellation, output caps, and diagnostics. Individual collectors do not duplicate this logic.

## Absence/removal semantics

“Not emitted this scan” is not the same as “uninstalled”.

A previous fact may only be downgraded/removed after applicable providers completed successfully and reconciliation has sufficient negative evidence. A timed-out/failed provider preserves the old fact with a verification warning.

This rule prevents partial scans from corrupting machine truth.

## Windows inventory sources

V1 is Windows-first.

For installed applications, use structured Windows sources first:

- Uninstall Registry keys (user/machine, 32/64 views);
- winget identity/update enrichment;
- specialized providers where needed (MSIX/AppX, VS, version managers, etc.);
- filesystem/index discovery only for gaps such as portable/custom installs.

Do not use `Win32_Product` / `wmic product` for routine inventory.

## Project discovery

Projects are discovered from configurable workspace roots and high-signal fingerprints rather than source-file crawling. Discovery handles `.git` directory **and file**, manifests/lockfiles/workspaces, nested repositories and monorepos.

Directories such as dependency caches/build output are skipped; links/reparse points are not followed by default.

A discovered repository becomes a long-lived `context/projects/` record only when it is useful enough to retain. Temporary clones/caches should not pollute persistent context.

## Environment scopes

Windows host is V1 primary scope. WSL is recorded as a related but distinct environment; V1 does not flatten Linux runtimes/package managers into Windows facts. Future multi-environment support should extend scope/profile concepts rather than reinterpret existing IDs.

## Freshness without diff noise

Exact per-item check times belong in ignored local state. `context/status.json` carries compact published verification/provider-health information plus an audit-closure projection. `provider_state` reports the current required-provider aggregate; `audit_closure` reports whether the documented Initial Audit closure is complete. Documented limitations may be accepted explicitly without being hidden; only open unknowns, conflicts, and unresolved entries block closure. The top-level `state` is the publication trust gate and is `verified` only when both are verified. Raw closure findings remain under `.local`.

A no-change scan should produce no semantic context diff. If the user chooses to publish a verification heartbeat, only compact status metadata should change instead of rewriting every item timestamp.

## Atomic publication

Collectors never mutate canonical context while scanning.

They write to `.local/staging`, then reconciliation -> schema/reference/privacy validation -> `CURRENT.md` rendering completes. Only then are proposed canonical files atomically installed into the working tree.

A failure before publication leaves the previous canonical context intact.

## Git concurrency

Both web and local agents may edit this private repository. Sync must therefore treat a dirty working tree or remote divergence as a state to reconcile, not something to force-overwrite.

A local full publication should normally be one logical Git commit. Force push is never part of routine sync.

## Extensibility

New software domains are additive files under `context/software/`, registered through `index.json`. New long-lived projects are individual JSON files registered by `projects/index.json`.

Avoid adding a database, daemon, platform abstraction, or GUI until real usage demonstrates a maintenance problem those components actually solve.

A future MCP/CLI may expose canonical/live context, but remains an access surface rather than a second source of truth.
