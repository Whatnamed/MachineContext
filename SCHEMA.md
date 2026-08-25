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

## Ownership: observed vs curated

When an entity mixes machine-detectable and semantic information, split ownership:

```json
{
  "id": "node",
  "kind": "runtime",
  "name": "Node.js",
  "observed": {
    "present": true,
    "version": "22.x",
    "executable": "D:\\path\\node.exe",
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

Routine collectors may replace/update `observed` after reconciliation. They must preserve `curated` unless an explicit semantic edit is requested.

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

Typical curated fields may include:

```text
status: active | inactive | legacy | testing | broken | unknown
role: primary | secondary | project-only | optional
purpose
constraints
notes
```

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

The full multi-scope schema can evolve later, but V1 data must not make future separation impossible.

## Compatibility

V1 evolution should be additive whenever practical. New software categories are new JSON modules registered by `context/software/index.json`; new long-lived projects are new JSON files registered by `context/projects/index.json`.

Breaking changes require a root `schema_version` bump plus a migration plan. Do not casually rename stable IDs or reinterpret an existing field's meaning.
