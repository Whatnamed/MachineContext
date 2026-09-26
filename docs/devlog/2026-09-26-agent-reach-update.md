# Devlog — 2026-09-26 Agent Reach update + upstream tool refresh

Scope: update the existing Agent Reach install to upstream `main` in place, refresh the upstream tools it depends on that were already installed, refresh the bundled agent skill, run `doctor` as the acceptance check, and record the result in MachineContext. No other tool was installed, upgraded or reconfigured; DSH, OMP, the Parallel MCP server and all login/cookie state were left untouched.

Nothing was logged in or re-authenticated during this round, and no optional channel or backend was installed.

## What the pre-update state actually was

| Fact | Value |
| --- | --- |
| executable | `%USERPROFILE%\.agent-reach-venv\Scripts\agent-reach.exe` |
| version reported | `Agent Reach v1.5.0` |
| `agent-reach check-update` | `当前版本: v1.5.0` / `✅ 已是最新版本` |
| interpreter | the venv's own Python 3.12.10 |
| install provenance | `direct_url.json` → `https://github.com/Panniantong/agent-reach/archive/main.zip` |

**`check-update` was wrong, and this is the load-bearing finding.** The installed tree was stale even though it already said v1.5.0: upstream has not bumped `__version__` since 2026-06-11, so any 1.5.0 build answers "已是最新版本". Comparing the installed `agent_reach/` package against upstream `main` (`a19a171f`, 2026-09-15) file by file showed ~40 differing files, including a `channels/boss.py` that did not exist locally. Version strings therefore cannot decide whether an Agent Reach update is needed on this machine; compare package contents or reinstall from `main.zip`.

## Update performed

Reinstalled from the official archive through the venv's own interpreter — no second environment was created and nothing was installed from PyPI:

```
%USERPROFILE%\.agent-reach-venv\Scripts\python.exe -m pip install --upgrade --force-reinstall --no-deps \
  https://github.com/Panniantong/agent-reach/archive/main.zip
```

`--force-reinstall` was required precisely because the version number does not move. Content equality with `main` was then verified file-by-file (SHA-256, `__pycache__` excluded): identical. The new tree adds the facebook/instagram/boss channels, `references/finance.md`, and upstream's read-only doctor.

Upstream tools, restricted to what was already installed:

| Tool | Before → After | How |
| --- | --- | --- |
| yt-dlp (in the Agent Reach venv) | 2026.6.9 → **2026.8.19** | `pip install --upgrade "yt-dlp[default]>=2026.07.04"` — upstream `main` now declares that dependency; the `[default]` extra pulled in brotli, mutagen, pycryptodomex, websockets, yt-dlp-ejs |
| OpenCLI (`@jackwener/opencli`) | 1.8.4 → **1.8.8** | `npm update -g` in the existing `E:\Dev\npm-global` prefix |
| MCPorter | 0.9.0 → **0.9.0 (unchanged, deliberately)** | see below |

`twitter-cli`, `bilibili-cli`, `rdt-cli` and `xiaohongshu-cli` were **not installed before this round and were not installed now**; the guide's "upgrade only what is already installed" rule was applied literally. Nothing was uninstalled either — retreated backends stay as fallbacks.

**MCPorter could not be moved.** `npm update -g mcporter` (the guide's step) was run and correctly moved nothing, because every release from 0.10.0 on declares `engines.node ">=24"` while this machine runs Node 22.23.2. Forcing 0.14.1 would install an unsupported package; upgrading Node is a separate, larger migration that this round did not take on. Agent Reach is unaffected either way — its `mcporter`-based channels read `%USERPROFILE%\.mcporter\mcporter.json` directly instead of pinning a CLI version. Recorded on the entity so a future round does not read it as an oversight.

## Skill refresh

The agent skill was refreshed with `agent-reach skill --install` into `%USERPROFILE%\.agents\skills\agent-reach` and `%USERPROFILE%\.claude\skills\agent-reach` (13-platform → 16-platform version, adds `references/finance.md`).

Safe to overwrite, and checked before doing so rather than assumed: the on-disk files were byte-identical to the bundled skill of the previous install after normalizing CRLF, i.e. an unmodified bundled copy with no user customizations to protect. `SKILL_en.md` stays inside the package and is not copied into the agent skill directories.

## Doctor: the channel count drop is a semantics change, not a regression

`doctor` went from `10/13 个渠道可用` to `5/16`. That is upstream deliberately becoming more honest, not damage from this round: commits `6d67d705` ("make health checks truthful and read-only") and `b3367260` ("make diagnostics provably read-only") stopped proving things doctor cannot prove without side effects.

| Channel | Before | After | Why |
| --- | --- | --- | --- |
| GitHub | ✅ ok | [!] warn | `gh auth status` is no longer run (it writes a device-id); the binary and explicit auth config are still detected |
| 全网语义搜索 (exa_search) | ✅ ok | [!] warn | doctor no longer starts the remote MCP service to prove reachability |
| Twitter / Reddit / 小红书 | ✅ ok (`active_backend: OpenCLI`) | [!] warn (`active_backend: null`) | OpenCLI is now judged from the live loopback `/status` endpoint instead of `opencli daemon status`, which mutates `%USERPROFILE%\.opencli` |
| B站 | ✅ ok (OpenCLI) | ✅ ok (`active_backend: B站搜索 API`) | OpenCLI unverified, so it falls back to the public search API |
| YouTube | ✅ ok (yt-dlp) | ✅ ok (yt-dlp) | unchanged — the yt-dlp upgrade did not disturb it |
| V2EX / RSS / web | ✅ ok | ✅ ok | unchanged |

At check time Chrome was running and the OpenCLI extension was present (`ildkmabpimmkaediidaifkhjpohdnifk`, `1.0.24_0`, Default profile), but the OpenCLI daemon was not running on `127.0.0.1:19825`, which is exactly the state the new probe refuses to call "available". No login, cookie read or extra `opencli` invocation was performed to force the display green, per the round's constraints; the daemon starts on first real use.

## Canonical changes from this round

- `context/software/development.json`:
  - **new entity `agent-reach`** — the install was previously only observable indirectly through the `%USERPROFILE%\.agent-reach-venv\Scripts` entries in the `pip`/`python` `command_resolution`. Added as a supplementary entity (no routine provider covers it, same class as `mcporter`/`opencli`) with its executable, venv root, version and provenance notes. Values were produced with the repository's own `Resolve-McPersistentCommand`, not hand-written, and it was registered in `meta.supplemental_inventory.entity_ids` so the manual-refresh expectation is explicit. No collector or schema change was needed.
  - `opencli` version 1.8.4 → 1.8.8 (same install root).
  - `mcporter` — curated note recording the Node ≥24 engine constraint.
- No change to `context/machine.json` categories, collectors, scripts or tests: yt-dlp is documented on the `agent-reach` entity rather than promoted to its own entity, because its lifecycle belongs to that venv rather than to a user-managed PATH tool.

## Gates

See the publish commit. `tests/run-tests.ps1` PASS; `sync.ps1` overall health `success` with validation `ok`; `validate.ps1` 0 findings; second sync idempotent apart from the `status.json` heartbeat; privacy sweep over the diff clean.

## Open items (not fixed here, by design)

- The OpenCLI-backed channels read `[!]` until the daemon is running; nothing was changed to force a green reading.
- MCPorter stays at 0.9.0 until Node is upgraded to ≥24.
- `boss`, `linkedin`, `xiaoyuzhou`, `xueqiu`, Facebook and Instagram remain unconfigured — deliberately out of scope for this round.
- Upstream `check-update` compares only the version string, so it will keep reporting "already latest" while `main` moves. Reinstall from `main.zip` (or compare contents) when in doubt.
