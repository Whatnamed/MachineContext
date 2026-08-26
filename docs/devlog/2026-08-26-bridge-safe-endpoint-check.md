# 2026-08-26 — Allowlisted bridge endpoint check

The historical `%USERPROFILE%\\.config\\openai-api-server-via-codex\\config.toml` was checked through a narrow allowlist. The only retained configuration fact is that the bridge is configured for port `18080`; authentication, URLs, credentials, arguments, and raw configuration contents were not retained.

A contemporaneous read-only listener check found no listener on `10100` or `18080`. This strengthens the evidence that `18080` is a historical/configured bridge endpoint, but does not prove that the bridge is active, that it is the current primary endpoint, or that it should become canonical. The G1/G2 check therefore remains unresolved and confirmation-gated in ignored `.local` evidence.
