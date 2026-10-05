# Devlog — 2026-10-05 CLI / developer-tool maintenance round

Scope: bring the explicitly named CLIs up to official stable latest only where actually
behind, keep every existing install root / command resolution / install model, verify
configs and global rules, refresh the two supplemental-inventory entities the routine
providers cannot see, and publish. Explicitly out of scope and left untouched: Lark CLI,
OpenCodex, MCPorter (stays 0.9.0 with its Node>=24 constraint), Node/npm, and the
"already latest" group (Agent Reach, OpenCLI, GitHub CLI, Git, DSH, Bun — re-probed and
all still match canonical, nothing to report).

Baseline was read from the repo (`origin/main` = `ad74b28`), not from the task brief.

## Upgrades (before → after, official channel, mechanism)

| Tool | Before → After | Official stable latest at execution time | Mechanism actually used |
| --- | --- | --- | --- |
| Agy | 1.2.14 → **1.2.16** | GitHub `google-antigravity/antigravity-cli` latest non-prerelease `1.2.16` (2026-10-03) | `agy update` (native updater; verification + install steps all green) |
| Claude Code | 2.1.285 → **2.1.289** | npm dist-tags `latest: 2.1.289`, `stable: 2.1.285`, `next: 2.1.289` | `npm install --prefix D:\Claude\cli @anthropic-ai/claude-code@2.1.289` — dedicated prefix, default dist-tag lineage; the `stable` tag is again *older* than `latest`, so the 2026-09-25 disambiguation caveat still applies |
| Codex CLI | 0.159.2 → **0.160.0** | npm `latest: 0.160.0` (`alpha: 0.162.0-alpha.14` not used) | `npm install --prefix E:\Codex\codex-cli @openai/codex@0.160.0`; `%USERPROFILE%\.codex` and the Desktop runtime untouched. Codex Desktop auto-updated itself twice inside this round's window (26.928.2636.0 → 26.930.3930.0 → 26.930.4958.0, routine drift recorded by the syncs; the published canonical carries the final 26.930.4958.0 with its matching `cua_node`/`cua_repl` paths in `mcp.json`) |
| OMP / Oh My Pi | 18.4.4 → **18.6.1** | GitHub `can1357/oh-my-pi` latest non-prerelease `v18.6.1` (2026-10-04) | `omp update` (native updater, sha256-verified in place at `D:\OMP\omp.exe`; new `omp.exe.1791175877717.23180.0.bak` left alone, updater-managed) |
| Grok Build CLI | 1.0.44 → **1.0.46** | `x.ai/cli/stable` → `1.0.46` (`alpha` 1.0.49 not used) | `grok update` (native updater; `D:\GrokBuild\home\bin\grok.exe` in place, `grok.exe.old` parked by the updater) |
| Agently CLI | 1.0.5 → **1.0.18** | npm `latest: 1.0.18` for `@tencent-qqmail/agently-cli` | `npm install -g @tencent-qqmail/agently-cli@1.0.18` in the existing prefix `E:\Dev\npm-global` — plus the provenance correction below |
| Codex Threadripper | 0.3.4 → **0.3.6** | npm `latest: 0.3.6` | `npm install -g codex-threadripper@0.3.6` in the existing prefix; no `engines` field on 0.3.6 |
| uv / uvx | 0.12.21 → **0.12.23** | GitHub `astral-sh/uv` latest `0.12.23` (2026-10-03) | `uv self update` — in place at `E:\Dev\uv`, both binaries land on 0.12.23 |
| Supabase CLI | 2.118.0 → **2.119.0** | GitHub `supabase/cli` `v2.119.0`; npm `latest: 2.119.0` | new versioned prefix `D:\Tools\SupabaseCLI\2.119.0` (own package.json pinning supabase 2.119.0) + exactly one user-PATH segment repointed (index 17 of 28, `REG_EXPAND_SZ` preserved, nothing added/removed; 2.118.0 directory left in place per the established model) |
| Rust stable / Cargo | 1.98.1 → **1.99.0** | `rustup check`: `1.98.1 → 1.99.0 (b940084d7)`; upstream channel date 2026-10-01 | `rustup update stable` on the single existing `stable-x86_64-pc-windows-msvc` toolchain (`rustup toolchain list` still exactly one); rustup itself already current at 1.29.1 |
| Git LFS | 3.7.1 → **unchanged** | upstream `v3.8.0` | bundled copy inside Git for Windows 2.55.0.5 — only moves with that installer (2026-10-01 record stands; the Git-for-Windows process-lock window still doesn't exist inside an agent session) |

Deliberately not upgraded: none besides the out-of-scope list — every in-scope target had a
real stable update and received it.

## Agently CLI: provenance corrected (evidence-based)

The canonical purpose said "Agently application framework CLI". The machine says otherwise:

- `E:\Dev\npm-global\agently-cli.cmd` actually launches
  `node_modules\@tencent-qqmail\agently-cli\scripts\run.js`;
- the installed package.json declares name **`@tencent-qqmail/agently-cli`**,
  description **"Agent-first mail CLI for Agently"**, Apache-2.0, engines `node>=16`;
- the npm registry has **no package named `agently-cli`** (`npm view agently-cli` → 404),
  so the plain name must never be used for install/update commands.

`purpose` was corrected to the Agently Mail CLI wording and two curated notes record the
evidence and this round's update. `agently-cli --help` ("auth login … stores token in
keychain") is consistent with the mail-CLI reading.

## Verification

- Config/global-rules preservation: sha256 of `%USERPROFILE%\.gemini\config\GEMINI.md`,
  `.gemini\antigravity-cli\settings.json`, `.claude\CLAUDE.md`, `.codex\config.toml`,
  `.codex\AGENTS.md`, `.omp\agent\config.yml`, `.omp\agent\models.yml`,
  `D:\GrokBuild\home\config.toml` — **byte-identical before and after**, including after
  the AI-CLI smoke tests (hashes in `.local/config-hashes-2026-10-05-*.txt`).
- Command resolution unchanged everywhere: `agy` → `%LOCALAPPDATA%\agy\bin\agy.exe`
  (junction to `E:\AGY\cli`), `omp` → `D:\OMP\omp.exe`, `grok` →
  `D:\GrokBuild\home\bin\grok.exe`, `claude` → `D:\Claude\cli\claude.cmd`, `codex` →
  `E:\Codex\codex-cli\codex.cmd`, `agently-cli` / `codex-threadripper` →
  `E:\Dev\npm-global\*.cmd`, `uv`/`uvx` → `E:\Dev\uv\*`.
- `--help` smoke OK on all updated tools.
- **Agy global-rules live-load re-verified on 1.2.16** with the established scratch-repo
  probe: from a scratch git repo with no `AGENTS.md`/`GEMINI.md`,
  `agy -p "<question answerable only from user-global rules>"` returned
  `E:\MachineContext\CURRENT.md` — a path that appears **only** in
  `%USERPROFILE%\.gemini\config\GEMINI.md`, so the user-global ruleset demonstrably
  reached the model. (The on-disk GEMINI.md hash is unchanged.)
- Minimal AI smokes (single-turn, no unnecessary calls): `claude -p` → `OK` exit 0 (with
  the pre-existing `unrecognized_model` notice for the configured `deepseek-v4-pro[1m]`
  alias); `codex exec --skip-git-repo-check "Reply exactly: OK"` → `OK` exit 0 — note
  0.160.0 in this harness reads the prompt only after stdin is closed
  (`< /dev/null` needed); `omp -p` → `OK` exit 0 (the `pencil` MCP connect warning is
  pre-existing local-path drift, unrelated: OMP's own configs are byte-identical);
  `grok -m dasu -p` → `OK` exit 0 (avoiding the known `grok-4.5` gateway-side
  `GROUP_DELETED`, still owed by the user).
- Supabase persistent-PATH simulation: with PATH rebuilt from the registry (machine+user),
  `Get-Command supabase` resolves only into `D:\Tools\SupabaseCLI\2.119.0\...` and
  `supabase --version` → 2.119.0.

## Canonical

- Collector-owned (routine sync): versions for `agy`, `claude-code`, `codex-cli`, `grok`,
  `omp`, `cargo`, `rustc`, `uv`, `uvx`; `supabase` version/executable/install root and
  PATH views; `codex-desktop` → 26.930.4958.0 with the matching `cua_node`/`cua_repl`
  path moves in `mcp.json` (auto-update drift, not this round; the Desktop updated twice
  inside the window — 26.930.3930.0 mid-round, 26.930.4958.0 by the final publish);
  storage free-space drift; heartbeat.
- Curated (one-time script `.local/curated-2026-10-05-cli-maintenance.ps1`, pwsh 7):
  `agently-cli` 1.0.5 → 1.0.18 + purpose correction + provenance notes;
  `codex-threadripper` 0.3.4 → 0.3.6 + note. Both are `meta.supplemental_inventory`
  entities with no routine provider, so this is the OPERATIONS §6/§8 route, exactly like
  the trae/zcode/agent-reach precedents.
- Expected non-round drift also in the diff, each checked against its known class:
  `codex-cli.json` `model_reasoning_effort` xhigh → high (user/Desktop-side config.toml
  edit, §4.1); `dsh.json` desktop `agent-default-model` provider `tokenrhythm` →
  `deepseek-account` (user-side Cordis patch edit, §4.3); `qoder.json`
  `mcp-router.json` `exists` flip (runtime-transient, §8).

## Two environment incidents during publishing (process record)

1. **A Windows PowerShell 5.1 invocation of `sync.ps1` published a degraded canonical
   state.** The runbook requires pwsh 7, but this session's shell tool *is* 5.1; the
   first attempt crashed one provider on the documented `SHA256::HashData` gap (Flutter's
   version probe) yet — because probe failures are fail-soft — still reached publish,
   leaving Flutter and WSL marked `unverified/failed` plus a session-injected
   `HTTP_PROXY`/`HTTPS_PROXY` env-projection drift. Nothing was committed. The clean pwsh-7
   rerun (after the blocker below) republished over it: all ten providers `success`,
   Flutter/WSL verified again, proxy env projection back to `[]`.
2. **`wsl.exe` is on this session's program blacklist.** `network.ps1` probes
   `wsl --status` / `wsl --list --quiet` every sync, and the blacklist kills the whole
   sync process (not fail-soft at the process level), so no publish was possible from
   inside the session until the user removed `wsl.exe` from Security Center → Command
   Security → Program Blacklist. Recording this so the next round knows why a sync may
   die without any script error.

## Out-of-round observation: flutter CLI currently unprobeable

`flutter --version` fails on this machine right now with
`CreateFile failed 231 (所有的管道范例都在使用中。)` from
`runtime/bin/process_win.cc` — reproducible outside any sandbox, while
`dart.exe --version` (same SDK, 3.11.5) succeeds and no dart/flutter processes are
running. The install itself looks intact (`bin/cache/dart-sdk` present, engine.version
present, version 3.41.9 preserved in canonical). No dart/flutter process was killed and
no cache repair was attempted — flutter is outside this round's scope; the collector's
designed degradation (`verification: unverified`, reason `failed`, version kept) is what
canonical now honestly records. If it persists into the next session, running
`flutter --version` from a plain terminal and possibly `flutter doctor`/cache repair is a
user-side follow-up.

## Gates

- `sync.ps1` (pwsh 7, `-AllowDirty` because the publishing session itself produces the
  diff): overall success, all 10 providers success, validation ok, 0 warnings.
- `validate.ps1`: run standalone below, expected 0 findings.
- Diff reviewed line by line: only the version/verification fields above, the two
  curated note sets, the expected non-round drift listed above, storage drift and the
  heartbeat. No schema or collector changes → per §2.3 the full test suite was not
  required and not run.
- Idempotency: a second sync changes only `context/status.json`'s `verified_at`
  heartbeat (checked by diff below).
- Privacy sweep over added diff lines: no key/token/cookie/bearer/authorization shapes;
  no credential content read anywhere (all config files only hashed; the Agy/Grok/Claude/
  Codex smokes used existing credentials without reading them).
