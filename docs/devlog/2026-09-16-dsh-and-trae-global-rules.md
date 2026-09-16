# Devlog — 2026-09-16 DSH user-global instruction file + TRAE Work CN global rule

Scope: fill the user-level global-rules gaps left by the 2026-09-15 round without redesigning the ruleset. The shared rule body stayed `.local/global-rules-canonical.md` (unchanged); each target received only the mechanical adaptation its product requires. Antigravity Desktop was investigated and deliberately left alone. Every previously deployed entry was re-checked for presence and duplicate injection.

## Newly deployed

| Product | User-level file | Mechanism (how the path was established) | Load verification |
| --- | --- | --- | --- |
| DSH 0.1.5-rc.2 | `%USERPROFILE%\.dsh\AGENTS.md` | `@deepseek-ai/dsh-agent-instructions` joins a fixed `USER_GLOBAL_FILE = "AGENTS.md"` onto `$DSH_HOME`; `DSH_HOME` is `%USERPROFILE%\.dsh`. Confirmed at both the plugin source (`lib/index.js`) and the composed web profile row | **Live injection**: the running DSH session received the file as a sourced `Instructions from: ~/.dsh/AGENTS.md` block, framed under `user-global` and preceding the project chain from `E:\MachineContext\AGENTS.md` |
| TRAE Work CN 0.1.58 | `%USERPROFILE%\.trae-cn\user_rules.md` | `product.json` sets `dataFolderName: ".trae-cn"`; the compiled `customRuleService` `globalFilePath` getter joins the product data folder with the literal filename `user_rules.md` | Product-level static evidence (see the path caveat below); no live GUI session was run |

- **TRAE path caveat (recorded, not guessed):** the file sits at the data-folder **root**. The directory-style `%USERPROFILE%\.trae-cn\user_rules\` is **not** the global rules location. Workspace-scoped rules are a different mechanism: `<workspace>\.trae-cn\rules\project_rules.md` (the service's `this.b = "rules"` is the workspace rules subdirectory, while `this.c = "user_rules.md"` is a single global file).
- **TRAE deployment was justified by actual use**, not installation presence: per-project agent memory under `%USERPROFILE%\.trae-cn\memory\projects` (`Morpho`, `Morpho-ui-trae`, `flclash-traffic-ledger`), `native-runcommand` tool-execution snapshots, and an agent log under `%APPDATA%\TRAE SOLO CN\logs`. Note this TRAE install is *TRAE Work CN / SOLO CN* (registry `TraeWork CN (User)`, appId 931506), not TraeCode CLI.
- Deployer: `.local/deploy-global-rules-2026-09-15.ps1` patterns reused; writes are byte-identical to the canonical body except the H1 title. Both new files were absent beforehand, so nothing was overwritten.

## Antigravity Desktop: deliberately NOT deployed

- The shipping runtime is `resources\bin\language_server.exe` (153 MB, language server 2.11.0), **not** `app.asar`. `app.asar` (4.5 MB, the Electron shell) contains zero `GEMINI.md`/`AGENTS.md`/`user_rules` strings and never resolves a rule path; its only `.gemini` references are data-dir and IDE-migration paths.
- The runtime's embedded customization documentation names `~/.gemini/config/` as the **global customization root**, with rules as `rules/*.md` relative to that root or as standalone `GEMINI.md`/`AGENTS.md` files. A concrete path construction (`.gemini/config/projects/.json`) confirms the root is resolved literally.
- Therefore Antigravity Desktop and Agy share the same global rules file — `%USERPROFILE%\.gemini\config\GEMINI.md` — which was already deployed on 2026-09-15. The 2026-09-16 round re-confirmed it present (3851 bytes, canonical hash) and did not rewrite it.
- `%USERPROFILE%\.gemini\GEMINI.md` was **not** created. The docs place global rules under the config root, but no runtime evidence positively excludes the parent `~/.gemini` directory as an additional candidate, and byte-identical duplicates would still be loaded twice by different consumers. Because that could not be ruled out, the pre-existing file was left untouched.

## Re-verified, unchanged

- Codex `%USERPROFILE%\.codex\AGENTS.md`, ZCode `%USERPROFILE%\.zcode\AGENTS.md`, Claude Code `%USERPROFILE%\.claude\CLAUDE.md`, Agy `%USERPROFILE%\.gemini\config\GEMINI.md`, Qoder `%USERPROFILE%\.qoder-cn\rules\global-personal-rules.md` — all present at 3851 bytes (Qoder 3886 due to its `always_on` frontmatter) and identical to the canonical body.
- Grok Build has no `AGENTS.md` in `D:\GrokBuild\home` **by design** (it would be injected in addition to the Claude-compat file); re-confirmed the grok-home copy is still absent, so there is no duplicate injection.
- `%USERPROFILE%\.trae\user_rules.md` does not exist, and `peerDataFolderNames` is `[".trae"]`, so the peer-product skill sharing feature cannot currently double-load the CN ruleset.

## Incidental real drift captured by the same sync (user's own changes, not caused by this round)

- DSH `agent-default-model.model` `glm-5.3-flash` → `deepseek-flash` (matches the live `settings.yaml`).
- Qoder CN desktop self-updated **0.1.2 → 0.1.3** and **recovered from the recorded startup failure**. The 2026-09-15 `FutureDatabaseVersionError` (DB schema v74 vs app-supported v64) no longer reproduces: the registry now reports `Qoder CN 0.1.3`, logs under `%USERPROFILE%\.qoder-cn\logs` are live, and `.qoder-app-status.json` shows a logged-in session at 2026-09-15T16:38Z. The 2026-09-15 curated note claiming recovery "requires updating the desktop app itself" was replaced with a RESOLVED note — leaving it would have kept a fixed blocker recorded as current.
- `%USERPROFILE%\.qoder-cn\mcp-router.json` is now absent (it was previously recorded as a sensitive runtime-credential file by path only); the routine config collector flipped `files[].exists` to false. Nothing under `.qoder-cn` matches `mcp-router*` any more.

## Canonical

- Deployed-rule `config_paths` added for `dsh` and `trae` (evidence `global-rules-deployment-2026-09-16`, provider `user-confirmed`); curated notes on both, plus the Antigravity Desktop resolution notes, via one-time script `.local/curated-2026-09-16-global-rules-round2.ps1`.
- Qoder entity refreshed via `.local/fix-2026-09-16-qoder-refresh.ps1`.
- Rule bodies are **not** copied into the repository; MachineContext records the path, owning tool, verification method, and inheritance/duplication relationships only.

## Gates

- `tests/run-tests.ps1`: all PASS.
- `sync.ps1 -AllowDirty`: all ten providers success, validation ok (0 warnings, 0 findings).
- Privacy sweep over `git diff context/`: only the expected paths, booleans and model/provider identifiers — no credential shapes.
