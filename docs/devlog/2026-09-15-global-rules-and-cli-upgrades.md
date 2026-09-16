# Devlog — 2026-09-15 global agent rules deployment + AI CLI audit/upgrade round

Scope: deploy one shared user-level global ruleset to every coding agent the user actually runs, audit the user-maintained AI CLIs against current official stable, upgrade where evidence allowed, and sync MachineContext. OpenCodex was explicitly excluded (recorded as inactive), as were bundled `qoderclicn`/`qodersec` and all auto-update desktop GUI apps.

## Global rules deployment (identical semantics; per-product mechanical adaptation only)

| Product | User-level file | Mechanism (verified how) | Load verification |
| --- | --- | --- | --- |
| Codex CLI/Desktop | `%USERPROFILE%\.codex\AGENTS.md` | Official global scope (`AGENTS.override.md` absent; codex docs) | `codex exec` answered YES + exact section headings |
| ZCode | `%USERPROFILE%\.zcode\AGENTS.md` | Official zcode-guide plugin doc: user default instructions, loaded before workspace AGENTS.md | Documentation-level (in-harness session test not possible from inside) |
| Agy | `%USERPROFILE%\.gemini\config\GEMINI.md` | agy's global customization root is `~/.gemini/config` (embedded docs), **not** `~/.gemini\GEMINI.md` as assumed | `agy -p` answered YES + exact headings |
| Qoder CN Desktop | `%USERPROFILE%\.qoder-cn\rules\global-personal-rules.md` (`trigger: always_on`) | Embedded desktop runtime (`qoder-worker-runtime.obf.mjs`) enumerates `<globalDir>\rules` (RuleHandler) and `<globalDir>\AGENTS.md` (scope "home") with `globalDir` = `.qoder-cn`; official runtime docs define user-level rules/AGENTS.md | Engine-level static evidence + docs; live GUI test blocked by the pre-existing startup failure below |
| OMP | none (reads the Codex file) | Binary contains context source descriptor "Load context files from ~/.codex/AGENTS.md (user-level only)" | ⚠️ **RETRACTED 2026-09-16** — the original entry claimed ``omp -p`` reproduced the six section headings, but that run happened from inside `E:\MachineContext`, so the headings observed were the **project** file, not the user-global one. Re-tested from a scratch directory with `.git` but no `AGENTS.md`: no instruction file is injected, on 18.2.1 **and** on 18.1.21 (controlled A/B swap of the saved `.bak`). OMP must be treated as **not covered** by the shared global ruleset until re-verified with a project-directory-isolated test. **Subsequently RESOLVED on 2026-09-16** — the cause was an opt-in context-source gate (`enabledProviders` did not list `codex`); it is fixed and OMP now loads the user-global rules additively with project rules. See `2026-09-16-omp-upgrade-and-global-rules-verification-correction.md` |
| Claude Code | `%USERPROFILE%\.claude\CLAUDE.md` | Official user memory path (file did not exist before) | Official-path mechanism; model-level test returned HTTP 402 from the user's custom gateway (no balance) — not a mechanism failure |
| Grok Build | none in grok home | Grok injects BOTH `<grok-home>\AGENTS.md` and `~/.claude/CLAUDE.md` (Claude compatibility) — verified via `grok inspect --json` (2 × 962 tokens, no dedupe). Kept the Claude file as the single source; the grok-home copy was removed | `grok inspect --json` after: exactly 1 global instruction (962 tokens) |

- The previous `%USERPROFILE%\.codex\AGENTS.md` (a one-line pwsh-7 preference) is backed up at `.local/backup-codex-AGENTS-2026-09-15.md`; its semantics are covered by the shared ruleset.
- Rule body source of truth for this session: `.local/global-rules-canonical.md`; deployer: `.local/deploy-global-rules-2026-09-15.ps1`.

> **Method correction added 2026-09-16 (applies to every row in the table above).** A "does the global ruleset load?" test is only valid when the agent was invoked from a directory that does **not** itself contain an `AGENTS.md`/`CLAUDE.md`. Running it from `E:\MachineContext` (which owns a project file) satisfies the model with *project* content and reads as a pass even when the user-global file is ignored. The OMP row was wrong for exactly this reason. For any future re-check: run from a scratch directory containing `.git` but no instruction file, and confirm the reproduced headings match the **user-global** file, not the project one. The other rows' mechanisms are documented official paths rather than behavioural tests, so they are unaffected; the runtime-verified ones (Codex, Agy, Grok) were checked with tooling that reports actual loaded sources and remain valid.

## Version audit and updates (all primaries preserved)

| Tool | Before → After | Channel check | Mechanism |
| --- | --- | --- | --- |
| Agy | 1.1.27 → 1.2.2 | Official updater manifest stable = 1.2.2 | Already self-updated unattended by the native updater; nothing to do |
| Codex CLI | 0.153.4 → 0.154.0 | npm `latest` = 0.154.0 (GitHub releases only carry alpha notes; no stable notes published) | `npm install --prefix E:\Codex\codex-cli @openai/codex@0.154.0` |
| Claude Code | 2.1.241 → 2.1.270 | dist-tags: `latest` 2.1.270, `stable` 2.1.236 — **below** the local version, so the `stable` tag must never be used here (downgrade risk); changelog 2.1.242–2.1.270 = fixes incl. Windows fixes, no breaking config changes | `claude update` renamed `bin\claude.exe` aside and then failed, leaving no binary; restored from `claude.exe.old.*`, then completed with explicit `npm install --prefix D:\Claude\cli` + `HTTPS_PROXY` set (postinstall downloads the native binary and needs the proxy) |
| OMP | 18.1.10 → 18.1.21 | updater-reported latest | `omp update` (in-place, sha256-verified) |
| Grok Build | 1.0.13 → 1.0.30 | Official stable channel (`grok-build-public-artifacts/cli/stable`) = 1.0.30; no published release notes (closed product) | `grok update` is broken on this layout ("Auto-update failed: program not found"; its npm-reinstall hint would create a second install). Copied the official stable artifact `grok-1.0.30-windows-x86_64.exe` over `grok.exe` in place (backup `grok.exe.bak-1.0.13`). The official `install.sh` was deliberately not used because it appends a PATH block to shell config |
| DSH | 0.1.1-rc.2 → 0.1.5-rc.1 | npm `latest` = 0.1.5-rc.1 — RC tags are this package's normal channel; notes: session data format V3 migration (automatic, originals preserved, no downgrade-read), new default model applies to new sessions only | `npm install --prefix D:\DSH @deepseek-ai/dsh@0.1.5-rc.1` |

- **Duplicate-install incident (cleaned):** `claude update`'s "global installation update method" also installed `@anthropic-ai/claude-code@2.1.270` into `E:\Dev\npm-global` (npm `prefix -g`), which the routine provider then surfaced as a second `claude.cmd` resolution. Removed the same session via `npm uninstall -g @anthropic-ai/claude-code`; `Get-Command claude` resolves only to `D:\Claude\cli` again. Lesson recorded: on this machine run `claude update` with the proxy env set and verify single-install afterwards.
- Post-update smoke checks: `--version` + `Get-Command` resolution verified for all six; `grok inspect` confirms config sources and the global rules still load on 1.0.30.

## Qoder CN Desktop: pre-existing startup failure (unrelated to the rules deployment)

- The app (0.1.2) fails to start: `FutureDatabaseVersionError: 本地数据库版本 74 与当前版本 64 不兼容` against `%APPDATA%\com.qodercn.app.stable`. `main.sqlite` was last written 2026-09-06; a zombie tray instance had been running since 2026-09-14 and was the only live instance during this round.
- Recovery requires updating the desktop app itself — explicitly out of scope (desktop apps self-update; bundled components untouched). Recorded as a curated note on the qoder entity.
- The Qoder rules deployment therefore carries engine-level evidence (runtime enumeration + official docs) instead of a live GUI session.

## Canonical

- Routine providers refreshed: agy 1.2.2, claude-code 2.1.270, codex-cli 0.154.0, codex-desktop 26.901.5280.0 → 26.908.4834.0 (auto-update), dsh 0.1.5-rc.1, grok 1.0.30, omp 18.1.21.
- Curated additions (one-time script `.local/curated-2026-09-15-global-rules.ps1`, user-confirmed evidence `global-rules-deployment-2026-09-15`): `config_paths` entries for the deployed global rule files (codex-cli, claude-code, agy, zcode, qoder); inheritance/verification notes for omp and grok; the qoder startup incident; opencodex `status: "inactive"` + "installed but no longer used (2026-09-15 decision); not uninstalled".
- Incidental real drift captured by the same sync (user's own changes, not caused by this round): codex config.toml → model `gpt-5.6-luna`, effort `max`; OMP modelRoles default → `google-antigravity/gemini-3.8-flash`; ZCode BigModel providers disabled and GLM-5-Turbo model entries removed; NVIDIA driver 610.88 → 616.92; storage free-space changes.

## Gates

- `validate.ps1`: 0 findings. Privacy sweep over `git diff context/`: clean. Second sync: idempotent (heartbeat only). `tests/run-tests.ps1` not applicable: no collector, lib, or test changes in this round.
