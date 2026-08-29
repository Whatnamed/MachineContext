# Schema Notes

MachineContext intentionally starts with a small, explicit JSON contract rather than a large framework or database schema.

The root manifest is `machine-context.json`. Consumers should use its paths rather than hard-coding every future module.

## Serialization rules

Canonical structured files are JSON:

- UTF-8;
- 2-space indentation;
- stable property ordering produced by repository helpers;
- deterministic ordering for sets/lists whose semantic order is irrelevant;
- final newline;
- no comments inside JSON — explanatory text belongs in `notes`, `curated`, or docs.

PowerShell maintenance code must use repository JSON helpers rather than each collector independently serializing files.

### PowerShell value contract

Before serialization, every value is classified explicitly:

- scalar: `null`, strings/chars, primitive values, decimals, timestamps, GUIDs, and URIs;
- mapping: `IDictionary` or an actual `PSCustomObject`;
- sequence: arrays, lists, or other explicit `IEnumerable` collections, except strings, mappings, and scalar values.

`Copy-McValue` recursively clones mappings and sequences while preserving empty, single-item, and multi-item arrays. `ConvertTo-McStableObject` uses the same classification. JSON round-tripping is not used to guess a source value's type, and unsupported object types fail rather than expanding their .NET adapter properties.

Canonical JSON must never contain collection metadata such as `SyncRoot`, `IsFixedSize`, `IsReadOnly`, `LongLength`, or `Rank`. The validator rejects those properties and rejects literal current-user profile paths where `%USERPROFILE%` normalization is sufficient.

## Ownership: observed vs curated

When an entity mixes machine-detectable and semantic information, split ownership:

```json
{
  "id": "node",
  "kind": "runtime",
  "name": "Node.js",
  "observed": {
    "present": true,
    "version": "22.23.2",
    "executable": "D:\\Node.js\\Node.js\\node.exe",
    "install": {},
    "evidence": []
  },
  "curated": {}
}
```

Routine collectors may replace/update `observed` after reconciliation. They must preserve `curated` unless an explicit semantic edit is requested.

Curated fields are strictly optional. Canonical presence indicates that the software/project exists; redundant `status: active` or generic encyclopedia definitions are omitted. Curated fields are reserved for actionable user intent (e.g., `role: primary`, `status: legacy`, specific tool purpose, or machine constraints).

## Curation confirmation

User confirmation in conversation is authoritative for establishing semantic intent, project purposes, and supplemental inventories.

For optional batch or scripted curation workflows, `scripts/curate.ps1` provides an offline safety mechanism via a `g2-curation-confirmation` manifest (dry-run by default, applying only with explicit `-Apply`). It validates allowlisted `curated` fields without modifying `observed` facts.

Not every document must mechanically contain both sections. `conventions.json`, for example, is primarily curated. The ownership rule matters when automated and semantic fields coexist.

## Common identity fields

Use stable IDs independent of display name, version, and preferably install path.

Recommended common fields when applicable:

```text
id
kind/category
name
observed
curated
```

Identity may be backed by one or more source/provider IDs. The reconciler should merge multiple evidence sources for the same real entity rather than creating duplicates.

Display name is not guaranteed unique. Path is a fallback identity signal, not the preferred universal key.

## Evidence

Evidence is structured enough to explain where a fact came from without storing dangerous raw data.

Conceptual example:

```json
{
  "provider": "registry-uninstall",
  "provider_key": "safe-stable-key",
  "fields": ["version", "install.root"],
  "confidence": "high"
}
```

Do not store complete Registry/config/command output as evidence. Evidence should identify the source and useful normalized facts, not reproduce raw payloads.

## Provider health

Provider execution health is first-class and is summarized in local state and published `context/status.json`:

```text
success
partial
unavailable
timed_out
failed
```

A failed provider cannot provide negative evidence for removal.

## Observation verification state

When an observed record has a `present` field, its evidence state may be:

```text
verified-present
unverified
stale
verified-absent
```

`verified-present` requires a successful applicable direct/provider check. `unverified` is used after a failed, timed-out, or unavailable check while preserving the previous observed fields; it never means that software was removed. `stale` is an explicit retained state for facts that need a fresh check. `verified-absent` is reserved for a successful, high-confidence applicable absence check; the record remains in canonical JSON with `present: false` and a `last_known` observed snapshot. Provider health and observation verification are separate dimensions.

## Freshness

Do not update a timestamp on every entity during every no-change scan.

- exact `last_checked_at` belongs in ignored `.local/state.json`;
- `context/status.json` may publish compact scan/provider freshness;
- an item's optional change timestamp means the current observed value changed/was established, not merely that a no-change probe ran again.

This keeps Git diffs meaningful.

## Software records

Typical observed fields may include:

```text
present
version
executable
alternative_installations
install.root
install.method
install.scope
install.package_id
install.update_method
command_resolution
config_paths
data_paths
evidence
```

Typical curated fields (all optional):
```text
software status: legacy | testing | broken | compatibility-only (omitted for standard active tools)
role: primary | secondary | project-only | optional
purpose: short 1-line description (retained for AI/specialized CLIs; omitted for standard tools)
constraints
notes
```

Project lifecycle status is optional; canonical presence in `context/projects/` records its long-term project status. When explicitly required, projects use: `active | paused | maintenance | archived | experimental`.

Omit fields that have no value; do not manufacture large null-filled records.

## Projects

Project files describe how a long-lived local project connects to the machine. See `context/projects/_template.json`.

Observed project context may include:

- local path;
- sanitized repository identity;
- runtime/package-manager/tool/service refs;
- manifest/lockfile paths;
- common safe commands;
- local endpoints;
- discovered project/workspace type.

Curated context includes lifecycle/status, purpose, and important machine constraints.

The project repository remains source of truth for detailed dependency graphs.

## Relationships

Use stable entity IDs and record only relationships that improve planning or impact analysis.

Conceptual record:

```json
{
  "from": "dsh",
  "relation": "uses_shell",
  "to": "git-bash",
  "origin": "detected",
  "evidence": []
}
```

Useful relation types include `uses_shell`, `requires`, `uses`, `provided_by`, `managed_by`, `configured_with`, `reads_auth_from`, `connects_to`, `listens_on`, `deployed_by`, and `used_by_project`.

A relationship may be detected, inferred, or curated. Do not silently promote a weak inference into detected truth.

## Environment scope

V1 primary scope is the Windows host. Records that belong to another environment (WSL, container, project-local virtual environment) must carry or inherit an explicit scope instead of being flattened into Windows host state.

For Windows command/path facts, `windows-host` means the persistent Machine PATH followed by the persistent User PATH. The collector's current process scope is `collector-process`; its injected PATH and `Get-Command` results are diagnostics-only under ignored `.local` state and must not be published as host truth. A future WSL record uses the reserved `wsl:<distro>` form.

The full multi-scope schema can evolve later, but V1 data must not make future separation impossible.

## Configuration profiles

`context/configs/` stores safe, source-native projections of frequently edited AI harness configuration, registered by `context/configs/index.json` and `machine-context.json#canonical.configs_index`.

Module layout:

```text
context/configs/
  index.json      generated module registry + policy
  ai/<tool>.json  one profile per harness (omp, dsh, zcode, opencodex,
                  codex-cli, ...)
  mcp.json        cross-tool MCP inventory
```

Profile records keep the record envelope (`schema_version`, `id`, `kind: ai-config-profile`, `tool`, `observed`, `curated`) plus a `source` block:

```text
source.config_root        normalized config root
source.files[]            path/format/exists/role per relevant file
                          (env files, auth stores, history DBs: path+exists only)
observed.value_basis      'configured-local' — these are config declarations
observed.source_state     'current' for fresh projections; 'stale' when the
                          source files were confirmed absent during a scan
observed.source_state_reason    set alongside 'stale' (static text; git holds when)
observed.wire_verification 'not-wire-verified' when capability-like values
                          (contextWindow overrides, reasoning efforts) are local
                          policy, not verified upstream behavior
observed.projection       the sanitized source-native config subtree; real field
                          names (modelOverrides, thinking.efforts, compat, ...)
                          are kept so an AI can patch the actual config;
                          fields dropped by the per-field allowlist are listed
                          by name/path only in projection.unprojected_keys
observed.credential_env_names   environment-variable names referenced by the config
observed.redactions       paths/reasons for every dropped credential or unsafe value
observed.evidence         per-source-file provenance
```

Ownership and refresh follow the standard rules: the collector owns `observed` and refreshes it on routine scans; `curated` is user/agent-owned and preserved. A projector/provider failure keeps the previous record untouched; only a **confirmed source absence** downgrades the last-known profile to `source_state: stale`, and `index.json` modules carry the same `source_state`. Profiles are removed only through explicit cleanup.

The projection must never contain credential-named properties or credential values; `credential` fields survive only as environment-variable names. Provider/model-level unknown fields are dropped by the per-field allowlist and surfaced as `unprojected_keys` (names only). MCP records (`kind: mcp-inventory`) hold per-server tool/scope/name/transport/command/safe-URL plus allowlisted `args` and `env_names`; credential flags (`--token`, `-H`, ...) are dropped together with the argv they consume. Validators enforce these contracts (`config_sensitive_key`, `config_invalid_env_name`, profile/MCP record shapes) before publication.

## Compatibility

V1 evolution should be additive whenever practical. New software categories are new JSON modules registered by `context/software/index.json`; new long-lived projects are new JSON files registered by `context/projects/index.json`.

Breaking changes require a root `schema_version` bump plus a migration plan. Do not casually rename stable IDs or reinterpret an existing field's meaning.
