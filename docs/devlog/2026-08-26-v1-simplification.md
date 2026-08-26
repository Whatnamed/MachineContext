# 2026-08-26 — V1 Simplification and Inventory Integration

- Simplified curated semantics across all canonical modules: removed redundant status: active/unknown defaults and generic encyclopedia-style purposes for standard software, keeping curated sections clean and lightweight.
- Project lifecycle fields are no longer mandatory; canonical presence represents long-term project status while verified local project purposes are retained.
- Clarified inventory provenance: established meta.recorded_at, meta.refresh_policy: manual-broad-scan, and meta.source: user-confirmed-broad-inventory for creative.json and productivity.json to clearly separate them from routine core provider scans.
- Cleaned up conventions.json into explicit directory_roles, system_managed_roots, and non-strict drive_tendencies (D: / E: tendencies without flat-drive root discovery).
- Removed weak/incorrect associations: removed wrangler-config from codex-cli data paths and removed figma-agent provides figma from relationships.json.
- Compacted CURRENT.md into a high-signal AI entrance: routine development and AI tools remain fully expanded, while creative and productivity domains render as structured summary counts with JSON pointers.
- Feature-freeze: V1 is frozen for regular agent and user planning without further architectural rewrites.
