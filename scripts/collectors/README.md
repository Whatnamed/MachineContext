# Collector modules

Put read-only, domain-specific Windows collectors here. Prefer small collectors with stable normalized output over one monolithic scan script.

Planned V1 domains are defined in `docs/COLLECTION_SPEC.md` and implementation order in `docs/DEVELOPMENT.md`.

Collectors must fail soft when a tool is absent, avoid arbitrary file-content reads, and never collect secret values.

Discovery collectors are candidate-only: bounded filesystem and optional Everything
fingerprints must retain low confidence and never publish directly to `context/`.
