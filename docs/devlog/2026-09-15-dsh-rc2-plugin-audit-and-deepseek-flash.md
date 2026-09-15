# Devlog — 2026-09-15 DSH 0.1.5-rc.2, web plugin audit, TokenRhythm deepseek-flash

Scope: audit the third-party plugins mounted in the DSH `web` profile against what the 0.1.5 RC line actually ships, quarantine what is genuinely broken, step DSH `0.1.5-rc.1 → 0.1.5-rc.2` in place, add the `deepseek-flash` model to the existing `tokenrhythm` provider, and re-publish MachineContext. Agent presets and the `tokenrhythm` provider's protocol/base URL were explicitly out of scope.

## Headline: the `web` profile had been dead since the 2026-09-15 rc.1 upgrade, not since this round

`dsh web --no-open` aborted with `plugin tree failed to load`. Two independent causes, both introduced when the previous round replaced DSH 0.1.1-rc.2 with 0.1.5-rc.1 (the `^0.1.5-rc.1` ranges floated the official sub-packages to `0.1.5-rc.2`, which was already published on 2026-09-10):

1. **`@deepseek-ai/dsh-settings` API drift.** `installSettingsSection` and `settingsNamespace` no longer exist in the official tree (`grep -rl` over `D:\DSH\node_modules\@deepseek-ai` → 0 hits). Thirteen `0.3.5`-era rows still import them and fail at `import`, which aborts the whole loader group: `web-ui-settings`, `web-ui-market`, `web-ui-task-board`, `web-ui-describe-image`, `web-ui-desktop-launcher`, `web-ui-doctor`, `web-ui-skin-center`, `web-ui-better-sidebar`, `live-stats` (host half), plus `web-ui-dsh-aionui-panel`, `web-ui-dsh-perf`, `web-ui-plugin-manager`, `web-ui-git-graph` (browser half, `@deepseek-ai/dsh-client-runtime` / `-ui-primitives` / `-ui-slots` are no longer shipped at all).
2. **A stale profile symlink farm.** `~\.dsh\profiles\node_modules\@deepseek-ai\*` is an Aug-27 pnpm link tree; 9 links now point into `.pnpm/@deepseek-ai+dsh@0.1.1-rc.2_*` or at packages the npm layout no longer creates. Left in place — it is not what breaks boot, and repairing it belongs with whatever replaces the plugin family.

Last known-good `dsh web` boot in `D:\DSH\logs\dsh-web.log` is 2026-08-29.

Disposition: the 13 rows were disabled through the profile's existing id-targeted Cordis disable layer (`~\.dsh\profiles\web\cordis.patch.yml`, the same mechanism already used for `web-ui-pet` / `web-ui-remote-web-ui` / `web-ui-ssh`), with the reason and rollback recorded in a comment block. Six third-party rows stay mounted: `web-ui-compat`, `web-ui-community-plugins`, `web-ui-chat-recovery`, `web-ui-liangshen`, `web-ui-skill-explorer`, `web-ui-archive-manager`. Nothing was removed from the profile and no `node_modules` was touched, so `dsh plugin` (unusable here: it is a pnpm forwarder and pnpm is not installed) is not required to restore them. After the quarantine the boot log is empty apart from the URL line, the browser console reports no plugin-load failure, and the official slot tree renders exactly one `sidebar` and one `rightbar`.

## Plugin audit vs the official 0.1.5-rc.2 surface

Authoritative baseline is `dsh --profile web --dump-config` on the installed tree, not the upstream repo: `ui-sidebar`, `ui-sidebar-right`, `ui-sidebar-files`, `ui-sidebar-documentpreview`, `ui-layout`, `ui-deliverables`, `ui-workspace`, `ui-theme`, `dsh-client-ui-open-in-app` are all live in the RC line. Web Terminal is **not** — there is no terminal row; that stays a 0.1.6-alpha surface, so terminal-bearing plugins were judged against rc.2 only.

| Package | Version | Role | 0.1.5-rc.2 overlap | Verdict |
| --- | --- | --- | --- | --- |
| `@linxin666/dsh-web-all` | 0.3.5 | aggregate bundle + compat bridge | n/a (infrastructure) | keep (still mounted; `web-ui-compat` loads) |
| `dsh-better-sidebar` | 0.15.2 | right sidebar: explorer, editor, preview, **web terminal**, embedded browser, git panel, side conversation | sidebar/files/preview fully covered by official; terminal/browser/git/side-chat not | **partial** — kept on the terminal rule, then disabled anyway because it imports a removed export |
| `@linxin666/dsh-client-ui-aionui-panel` | 0.3.5 | retired right panel; upstream README states it can no longer be enabled and only carries the side-card settings entry | none (panel already removed upstream) | disabled: browser half requires the deleted `dsh-client-runtime` |
| `@linxin666/dsh-client-ui-plugin-manager` / `-community-plugins` / `-market` | 0.3.5 | npm/git install, community index, workshop browser | official has only a read-only inventory + config cards | `plugin-manager` disabled (removed `dsh-client-ui-primitives`); the other two still load |
| `@linxin666/dsh-client-ui-task-board` | 0.3.5 | task board + host cron + idle-sleep guard | official `ui-schedule` row is disabled in the RC roster | disabled: imports a removed export |
| `@linxin666/dsh-client-ui-git-graph` | 0.3.5 | branch selector + git graph | none | disabled: removed `dsh-client-ui-primitives` |
| `@linxin666/dsh-client-ui-skin-center` | 0.3.5 | custom skin assets + live try-on | official covers light/dark/system only, not custom palettes | partial — disabled anyway (removed export) |
| `@linxin666/dsh-client-ui-skill-explorer` | 0.3.5 | browse/enable/create skills | official `ui-skill` is only an input-trigger reference source | **keep**, still loads and its 技能中心 entry renders |
| `@linxin666/dsh-chat-recovery` | 0.3.5 | fork-edit / retry last failed turn | workflow, not UI | **keep**, still loads |
| `@linxin666/dsh-liangshen` | 0.3.5 | ships the 梁神模式 agent preset | agent preset — out of scope by instruction | **keep untouched** |
| `@linxin666/dsh-doctor` / `dsh-desktop-launcher` / `dsh-perf` / `dsh-tool-describe-image` | 0.3.5 | rescue mode / desktop shortcut / perf HUD / vision tool for text-only models | none are UI duplicates | disabled: all four hit the removed-export drift |
| `@mlgbnb/dsh-archive-manager` | 1.0.7 | preview/restore/delete archived sessions | archived-session browsing is 0.1.6-alpha | **keep**, still loads; its 归档管理 settings entry renders |
| `@linxin666/dsh-live-stats` | 0.1.20 | token estimate + TPS row | partial vs official `token-meter` / `session-stats` | disabled (removed export). Note `0.1.20` **is** npm `latest`, so there is no upstream fix to move to, and the user had already set `live-stats.enabled: false` in `settings.yaml` |
| `@linxin666/dsh-pet` / `dsh-remote-web-ui` / `dsh-ssh` | 0.3.5 | pet / scan-to-pair remote / SSH | pre-existing user choice | unchanged, still disabled by the user's own rows |

Net: no plugin was judged a pure UI duplicate worth removing on function-overlap grounds — the one full-surface duplicate (`dsh-better-sidebar`) also carries rc.2-absent capabilities. Every disable in this round is an incompatibility quarantine, not a de-duplication.

Rollback: delete the `2026-09-15 temporary quarantine` block from `~\.dsh\profiles\web\cordis.patch.yml` (pre-edit copy at `.local/dsh-rollback-20260915/cordis.patch.yml.pre-plugin-disable`). Durable fix is a plugin-family upgrade — upstream `@linxin666/dsh-web-all@0.3.22` exists and its published `web-ui-settings` / `skin-center` / `dsh-better-sidebar` tarballs no longer import the removed exports, but `@linxin666/dsh-live-stats` has no fixed release. Not attempted: out of scope, and the official install channel needs pnpm.

## Second unresolved breakage: all four user agent presets fail to mount

`@deepseek-ai/dsh-persona@0.1.5-rc.2` now declares `prefix: z.string().required()`. `~\.dsh\.agent-presets\{apex-standard,anchored-standard,pristine,liangshen}\agent.cordis.yml` (written 2026-08-16) set only `text` / `complete` / `includeRuntimeContext`, so the default preset fails: `preset "apex-standard" failed to mount … $.prefix missing required value`, and initial session creation errors. Official built-in presets (标准/PTC/极简/创造) still mount, so the picker works. Editing presets was explicitly out of scope, so nothing was changed; this blocks any end-to-end DSH session test and needs its own round.

## Version and configuration changes

- DSH `0.1.5-rc.1 → 0.1.5-rc.2` via `npm install --prefix D:\DSH @deepseek-ai/dsh@0.1.5-rc.2` (same in-place mechanism as the previous round; dedicated root kept, no npm-global). npm reported `changed 1 package`: the official sub-packages had already floated to `0.1.5-rc.2`, so only the CLI itself moved. Release `dsh-v0.1.5-rc.2` (2026-09-10) is feedback-dialog + delivered-file-card polish only — no feature-surface change. `--dump-config` before/after is byte-identical. Primary stays `D:\DSH\dsh.cmd`; `Get-Command -All dsh` resolves `dsh.ps1` / `dsh.cmd` / `dsh`, all inside `D:\DSH`, no new duplicate.
- `~\.dsh\settings.yaml`: one additive entry under `llm-pi-ai.providers.tokenrhythm.models` — `deepseek-flash` / `DeepSeek V4.1 Flash` / `contextWindow: 1000000` / `maxTokens: 384000` / `input: [text, image]`. Provider-level `api: openai-completions`, `baseURL: https://tokenrhythm.studio/v1` and `apiKeyEnv: TOKENRHYTHM_API_KEY` untouched; no `reasoningEfforts` / `compat` added. Field names checked against the real schema in `dsh-llm-pi-ai` (`modelFields = {name, contextWindow, maxTokens, input, reasoningEfforts, compat}`), which confirms `input` and rules out the invented `inputModalities`.
- Facts re-verified against TokenRhythm's own pages: `deepseek-flash`, upstream DeepSeek, 1M context, 384K max output, text+image, tools yes, cache yes, and `responses.available: false` on this route — so `openai-completions` is correct even though DeepSeek's first-party endpoint supports Responses. No conflict with the task premise.
- Credential handling: `TOKENRHYTHM_API_KEY` resolves from the `refs` block in `~\.dsh\.credentials.yaml` (configured = yes). Nothing was printed, copied, or written to `settings.yaml`.

## Verification

- `dsh --profile web --dump-config` exit 0 before and after both the version step and the settings step.
- Model catalog: Settings → 模型 → 基元律动 shows 12 models, `deepseek-flash` = #12 with 上下文窗口 `1M` and 最大输出 token `384K`; API 协议 still `openai-completions`. Cancelled out of the editor; `settings.yaml` diff is still exactly the 8 added lines, i.e. the UI wrote nothing back.
- Wire smoke against `https://tokenrhythm.studio/v1` with `model: deepseek-flash`, direct (not `deepseek-official`). Text: HTTP 200, replied `OK`. Tools: HTTP 200 with `tool_choice: "auto"` → `calculator {"expr":"21*6"}`; **`tool_choice: "required"` is rejected with `MODEL_TOOL_CHOICE_NOT_SUPPORTED`**, so forced tool calls are not available on this route. Vision: HTTP 200 on a 1284-byte red-circle PNG, replied "A red circle." (prompt tokens 227 vs 37 text-only, so the image really was consumed). Note the model returns `reasoning_content` and spends `reasoning_tokens` by default — the DSH-side equivalent was not exercised because of the preset failure above.
- Gates: `validate.ps1` 0 findings; second sync idempotent apart from the `status.json` heartbeat; privacy sweep over `git diff context/` clean. `tests/run-tests.ps1` not run — no collector, lib, script, or test changes in this round.

## MachineContext

Routine providers refreshed `dsh` 0.1.5-rc.1 → 0.1.5-rc.2 and the `dsh` config profile with the new model. The collector keeps projecting source `apiKeyEnv` to `credentialEnvName`, which is intended. No schema or collector change: the plugin inventory stays in this devlog only, per scope.
