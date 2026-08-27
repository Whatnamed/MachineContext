# AI & tool configuration inventory

## Scope

Added a `context/configs/` canonical module holding source-specific, allowlisted, sanitized projections of frequently edited AI harness configuration, plus a cross-tool MCP inventory. This session also integrated the freshly configured OMP tool into the machine context.

## Capability

- `scripts/lib/config-projection.ps1`: shared helpers — a fixture-tested YAML subset parser, a bounded TOML table reader, credential key denylist, environment-variable name shapes, unsafe-text patterns, URL sanitization, the safe projection walker, and the validator-grade sensitive key scan.
- `scripts/collectors/config-profiles.ps1`: per-tool projectors (OMP `config.yml`/`models.yml`, DSH `settings.yaml`, ZCode `config.json`/`setting.json`/`bot-config.json`, OpenCodex `config.json`) and the MCP inventory reader (Claude `mcpServers`, Gemini `settings.json`, Codex `config.toml` `[mcp_servers.*]`, Cursor `mcp.json`). All projectors accept injected root paths for fixture testing.
- Reconciliation writes profiles under `context/configs/ai/<tool>.json`, `context/configs/mcp.json`, and a generated `context/configs/index.json`, preserving `curated` on refresh.
- Validation gains profile/MCP record contracts, `config_sensitive_key` (recursive credential-named key scan over `configs/`), and `config_invalid_env_name`.
- `CURRENT.md` gains a compact "AI configuration profiles" pointer section; `machine-context.json` registers `configs_index`.
- Tests: 8 new fixture-driven cases covering the YAML parser, credential denylist, OMP/DSH/ZCode/OpenCodex projections, MCP arg sanitization, validator contracts, curated preservation, and deterministic serialization. Fixtures use obviously fake secrets (`sk-test-do-not-publish`, `fake-refresh-token`, `https://user:pass@example.com`).
- Docs: `COLLECTION_SPEC.md` section R (projection rules, A/B/C classes, refresh/removal), `PRIVACY.md` AI-configuration-projection boundary, `SCHEMA.md` config profile contract, `DECISIONS.md` D039.

## Machine sync findings

- OMP verified as `D:\OMP\omp.exe`, version 18.0.6 (intentionally pinned), config root `%USERPROFILE%\.omp\agent`. `settings.json` is currently absent (only `settings.json.bak`); the effective `shellPath` lives in `config.yml` and points to `D:\Git\Git\bin\bash.exe` (Git Bash, not WSL bash). `webSearchOrder` leads with `parallel`. `models.yml` declares openai-codex contextWindow overrides (372000), zhipu-coding-plan glm-5.3-flash overrides (contextWindow 1000000, thinking efforts low/high/max, defaultLevel max, compat.supportsReasoningEffort), and a tokenrhythm provider whose `apiKey` is an environment-variable reference (`TOKENRHYTHM_API_KEY`).
- Vanilla Pi could not be located anywhere on this machine: not on the persistent host PATH, not in npm/bun/pip/uv/cargo globals, not in WSL Ubuntu-24.04, no `~/.pi`, no Registry/ARP/Start-Menu entry, and not found in bounded D:/E: root scans. No canonical Pi entity or config profile was created; this remains an open unknown.
- DSH lives in `%USERPROFILE%\.dsh`: `settings.yaml` declares `llm-pi-ai` providers (opencodex via localhost bridge, aijws, openai, deepseek, tokenrhythm — all keyed by `apiKeyEnv` environment-variable names), `agent-default-model` = tokenrhythm/glm-5.3-flash, four agent presets (recorded as name+path only), and an `llm-deepseek` section.
- ZCode's effective provider config is the portable appdata copy `D:\ZCode\appdata\.zcode\v2\config.json` (newer and larger than the `%USERPROFILE%\.zcode\v2\config.json` copy, which is recorded only as a sensitive-config-copy with real API keys inside). Provider entries project name/kind/baseURL/enabled/models/reasoning/limits/modalities with `credential_configured: true`; `setting.json` records the provider family selection; `bot-config.json` records the single bot's provider binding.
- OpenCodex `~/.opencodex/config.json` projects listen port 10100, defaultProvider openai, per-provider adapters/baseUrls/model context windows/effort maps, claudeCode integration state, and sidecar models; `apiKey`/`apiKeyPool`/`apiKeys` are redacted to `credential_configured` flags. The historical 18080 bridge port does not appear in the current config; a ZCode custom provider named "Agent Bridge" still targets `http://127.0.0.1:18080/v1`.
- MCP inventory: claude-code (figma http, chrome-devtools stdio, pencil stdio), gemini-cli (pencil), codex-cli (pencil); cursor's `mcp.json` exists but is empty. OMP/DSH/ZCode/Agy have no file-based MCP configuration; OMP state DBs are never read.

## Verification

`pwsh tests/run-tests.ps1` passes (28 existing + 8 new assertions groups). `sync -Mode Quick -NoPublish` validates end-to-end with the new `config-profiles` provider reporting success; privacy scans (`credential-value` redactions recorded at 14 source paths, zero secret values in projections) and the sensitive-key validator gate publication.
