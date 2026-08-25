# Schema Notes

MachineContext intentionally starts with a small human-readable YAML contract rather than a large formal schema system.

The root manifest is `machine-context.yaml`. Consumers should use its paths rather than hard-coding every future module.

## Common metadata

Volatile records should use this shape where applicable:

```yaml
verification:
  state: verified        # verified | stale | pending | unavailable
  source: detected       # detected | manual | imported | inferred
  observed_at: null      # ISO-8601 timestamp when known
  command: null          # safe verification command when applicable
```

Use `inferred` sparingly. Inferred facts should never silently replace detected facts.

## Software identity

Software should have a stable `id` independent of display name or version.

```yaml
- id: node
  name: Node.js
  category: runtime
  status: active
  role: primary
  version: null
  executable: null
  install:
    method: null
    root: null
    update_method: null
  verification:
    state: pending
    source: detected
    observed_at: null
    command: "node --version"
```

Paths and fields may be omitted when irrelevant. Do not fill files with null-valued fields merely for visual consistency.

## Projects

A project record describes how a local project connects to the machine:

```yaml
id: example-project
name: Example Project
status: active
local_path: null
repository: null
runtime_refs: []
tool_refs: []
service_refs: []
manifests: []
commands: {}
constraints: []
verification:
  state: pending
```

The project's own manifests remain the source of truth for detailed package dependencies.

## Relationships

Use stable IDs:

```yaml
relationships:
  - from: dsh
    relation: uses_shell
    to: git-bash
```

Only record relationships that improve planning, impact analysis, installation, updating, or troubleshooting.

## Compatibility

V1 evolution should be additive whenever possible. New software categories should normally be new module files registered by the software index. New project records should be new project files registered by the project index.

Breaking changes require a schema-version bump in `machine-context.yaml`.
