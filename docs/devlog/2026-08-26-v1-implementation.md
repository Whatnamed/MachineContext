# 2026-08-26 — V1 implementation baseline

本次会话从私有远端同步 `Whatnamed/MachineContext` 到 `E:\MachineContext`，按 `AGENTS.md` 与 Read first 文档完成实现前审计，并落地首轮 V1 pipeline。

## Implemented

- Phase A shared PowerShell 7 runtime：deterministic UTF-8 JSON、stable IDs/sorting、environment-normalized paths、safe URL/repository identity、privacy-safe diagnostics、capped probe/timeout/process-tree kill、provider health、`.local` staging/state。
- Phase B structured read-only providers：Windows system/hardware/storage via CIM/.NET/allowlisted Registry values、shell/PATH resolution、runtime/package-manager/toolchain verifiers、AI command/config-path existence、proxy/allowlisted local ports/WSL host state。
- Phase C-D discovery/reconciliation：Registry Uninstall candidates、bounded project fingerprint search、optional `es.exe` adapter、candidate/evidence storage、stable entity merge、curated preservation、safe absence semantics。
- Optional `winget export` enrichment：仅在已有 `winget.exe` 时运行，原始导出留在 `.local`；超时/失败保留 provider diagnostics，不生成 canonical installed-app facts。
- Phase E-F project records plus validation/render/sync：verified Git projects can be promoted, manifest-only hits remain local candidates; proposed context is validated/privacy-checked/rendered before atomic publication.
- Deterministic timestamp hardening：JSON round-trip 遇到 PowerShell `DateTime` 时统一转 invariant ISO，避免本机 locale 把 `verified_at` 改写成文化相关格式。

## Verification

- PowerShell parser check passed for all scripts.
- Fixture/runtime tests pass, including missing command, stderr version, timeout, output cap, Unicode/path redaction, privacy guardrails, curated ownership, and provider-failure absence behavior.
- Real Full scan published successfully without installing or changing machine software/settings.
- Real provider summary: system/shells/AI/network/Registry/project fingerprints succeeded; runtime/toolchain is partial because some optional/known commands do not verify; Everything is unavailable and correctly degraded to bounded fallback; existing winget export timed out safely and remained local-only.
- Optional provider timeout/failure is excluded from aggregate health while remaining explicit in `.local/state.json` and the raw run diagnostics.
- A subsequent Full scan reached zero byte changes across 19 canonical JSON/Markdown files after bucketing volatile free space to 256 MiB.
- Final stabilized Full run recorded 99 winget candidates locally alongside 147 Registry candidates and 93 project fingerprints; only nine verified Git projects were promoted to canonical project records, all with curated lifecycle status still `unknown`.

## Follow-up

Project lifecycle/status and installation conventions remain semantic/curated decisions. Registry candidates, manifest-only projects, runtime verifier failures, and any provider conflicts remain in `.local` diagnostics/candidates until reviewed or explicitly promoted.
