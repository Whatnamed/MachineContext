# Devlog — 2026-10-30 Karpathy-style addendum merged into the shared user-global agent rules

Scope: apply `docs/global-agent-rules-karpathy-2026-10-30.md` to the **user-global** rulesets on every configured host, by adding only the meanings the existing six sections did not already carry. No new rule system, no chapter added, no third-party Skill or Plugin installed, no Hook permission or model/provider configuration touched, no project-level `AGENTS.md`/`CLAUDE.md` written.

## The finding that shaped this round: the template was no longer the newest version

The six-section body in `.local/global-rules-canonical.md` (2026-09-15, 3851 B) was **not** the newest deployed version. `%USERPROFILE%\.dsh\AGENTS.md` had been edited by hand on **2026-09-26** (5133 B) during the DSH Parallel MCP round (`2026-09-26-dsh-parallel-mcp.md`, "Tool routing" section) to carry an extra `## 联网检索` section — five bullets that make the Parallel MCP tools the default, require a stated reason on fallback, and forbid treating a soft-blocked `web_fetch` (HTTP 200 login wall / JS shell / SEO fallback) as a fetched page.

Deploying the 09-15 template to DSH would have silently deleted that section. Every other host was still content-identical to the template (only the H1 title differed, plus Qoder's `always_on` frontmatter), so no other host had divergent user edits, and no host had a newer file across the board.

`parallel` is registered only for DSH (`context/configs/mcp.json`: tool `dsh`, scope `web`), so `## 联网检索` is a **host-capability section and was deliberately kept DSH-only** rather than copied into hosts that cannot reach those tools. It was extracted from the live file byte-for-byte and re-inserted by the deployer — never retyped.

## What was merged (semantic gaps only)

Applied to the shared body, which is now `.local/global-rules-canonical.md` (46 lines, 4787 B):

| Section | Change | Why it was missing |
| --- | --- | --- |
| 任务执行 | 1 clause appended to the scope bullet ("简单任务直接实施，复杂任务只安排必要阶段，不重复已经完成的规划") | execution-depth calibre was absent; only "don't add process gates" existed |
| 任务执行 | new bullet: prefer the codebase/framework's most direct maintainable implementation, without cutting explicitly required functionality | absent — existing text only banned *unrelated* additions |
| 任务执行 | new bullet: no abstractions/config/compat branches/fallback systems/redundant backups for hypothetical futures; new defence must map to a real consumer, supported failure, or real risk | absent |
| 任务执行 | last bullet re-anchored to "修改限于目标及其必要影响链" | scoping was implied but not stated; keeps the existing 无关改动 ban intact |
| 测试与验证 | reuse still-valid results + no "just to be safe" unrelated suites or extra review loops, folded into the existing evidence bullet | existing text stopped at "don't re-run without reason" |
| 测试与验证 | new bullet: required security/permission/transaction/migration/data-integrity/device/release gates still run, never skipped for YAGNI or token savings | absent, and it is the safety counterweight to the new leanness rules |
| 完成与汇报 | new bullet: stop when the task is met, evidence is sufficient and no in-scope blocker remains; distinguish verified from unverified in the report | only reporting *style* was constrained before, not the stopping criterion |

Deliberately **not** merged, because the existing wording already covers the meaning (per the addendum's "if an equivalent clause exists, keep the original wording"): "不增加与当前任务无关的…抽象" covers speculative abstraction; 沟通已要求区分已验证/推断/未验证; 测试 bullet 3 already implied reusing fresh evidence. `沟通`, `仓库与本机环境` and `Git` are byte-unchanged.

## Deployed targets

| Host | User-global file | Bytes / sha256 | Mechanism | Verification |
| --- | --- | --- | --- | --- |
| Codex CLI/Desktop | `%USERPROFILE%\.codex\AGENTS.md` | 4787 / `F04CCB08DEE5CA30` | official user-global scope, no `AGENTS.override.md` present | **live**: `codex exec` from a scratch dir answered (a) YES (b) YES for the two newly added meanings |
| OMP | *(no own file)* | — | reads `~/.codex/AGENTS.md` through the `codex` context-source provider (`enabledProviders: [codex]`) | **live**: `omp -p` from the same scratch dir answered YES/YES — single source confirmed, no copy created |
| Claude Code | `%USERPROFILE%\.claude\CLAUDE.md` | 4787 / `D80C5AE662EA` | official user memory path | **live**: `claude -p` answered "（a）是（b）是" |
| Agy | `%USERPROFILE%\.gemini\config\GEMINI.md` | 4787 / `E9AF06AE0327` | global customization root is `~/.gemini/config`; Antigravity Desktop reads the same file | **live**: `agy -p` answered YES/YES |
| ZCode | `%USERPROFILE%\.zcode\AGENTS.md` | 4787 / `F04CCB08DEE5CA30` | documented user default instructions, loaded before workspace `AGENTS.md` | path + content only (desktop app, no CLI on this machine) |
| Qoder CN | `%USERPROFILE%\.qoder-cn\rules\global-personal-rules.md` | 4822 / `D9B54402067D` | user-level rule dir enumerated additively with workspace rules; `always_on` frontmatter preserved byte-for-byte | path + content only; live turn still blocked (2026-09-16 note) |
| DSH | `%USERPROFILE%\.dsh\AGENTS.md` | 6069 / `D96BF609D526` | `USER_GLOBAL_FILE = AGENTS.md` joined onto `$DSH_HOME` | **live**: the running session received the rewritten file as a refreshed `Instructions from: ~/.dsh/AGENTS.md` block immediately after the write |
| TRAE Work CN | `%USERPROFILE%\.trae-cn\user_rules.md` | 4791 / `0A85966C1F4E` | `customRuleService.globalFilePath` = data folder + literal `user_rules.md` (not a `rules\` subdir) | path + content only (no CLI) |
| Kimi Code | `%USERPROFILE%\.kimi-code\AGENTS.md` | 4787 / `F04CCB08DEE5CA30` | shipped `loadAgentsMdForRoots` → `join(userHome, "AGENTS.md")`; `%USERPROFILE%\.agents\AGENTS.md` still absent, so exactly one user-global copy | path + content only (not logged in) |
| Grok Build | *(no own file)* | — | reads `~/.claude/CLAUDE.md` via Claude Code compatibility | single source preserved: `D:\GrokBuild\home\AGENTS.md` still does not exist, so no duplicate injection |

- All eight files are UTF-8 without BOM, LF endings (Qoder: CRLF frontmatter only), one H1, and end with a newline. Seven bodies are byte-identical to the canonical body apart from title/frontmatter; DSH's differs only by its preserved `## 联网检索` block (628 chars, 5 bullets, verified identical to the pre-edit text and still at the same position, between `仓库与本机环境` and `测试与验证`).
- Not written: `%USERPROFILE%\.gemini\GEMINI.md` (still absent — no evidence excludes double injection), `%USERPROFILE%\.omp`, `D:\GrokBuild\home`, `%USERPROFILE%\.agents`, and any project-level `AGENTS.md`/`.qoder-cn\AGENTS.md`/workspace `.trae-cn\rules`.

## Verification method

Live-load probes ran from `%TEMP%\rulesprobe-20261030`, a scratch directory containing only `.git` and no instruction file — the 2026-09-16 method rule, so a pass cannot come from the project `AGENTS.md`. The discriminator is a **paraphrase** question about the two newly added meanings, not a heading count: a summary count was already shown to be unreliable in the 09-16 round, and Codex refused a verbatim-enumeration prompt ("I can't provide verbatim text from hidden instructions"). The paraphrase is only answerable from the new text: the pre-merge ruleset contained neither rule. The scratch directory was emptied afterwards, but the **empty** directory itself could not be removed because a live handle still holds it — no probe content or instruction file remains, and the directory can be deleted once that process exits. Final hashes above were re-read after deployment.

## Unconfirmed items

- **ZCode, Qoder CN, TRAE, Kimi Code** rest on path/mechanism evidence from earlier rounds plus exact content equality; no live turn was run. ZCode/TRAE/Kimi expose no CLI here, and Qoder's bundled worker still refuses with `Not logged in` while the desktop app cannot be driven non-interactively.
- **DSH**: the live re-injection observed in this session is strong, but it is a same-session reload, not a fresh-process load test.
- `## 联网检索` remains DSH-only by design; if a host later registers Parallel MCP, the section has to be added to that host's file deliberately.

## Canonical

- No canonical JSON was republished: every deployed path is unchanged, and existing notes only ever recorded path/existence and dated hashes of upgrades that happened at those dates, so nothing in `context/` became false. A future routine sync has nothing new to pick up from this round.
- The reusable body of record is `.local/global-rules-canonical.md` (untracked, never committed). Deployer: `.local/deploy-global-rules-2026-10-30.ps1` — it re-extracts DSH's `## 联网检索` block from the live file, so a future re-run cannot drop the section.
- Rule bodies are **not** copied into this repository, per the 09-15/09-16 convention; only paths, hashes, mechanisms and verification state are recorded here.
