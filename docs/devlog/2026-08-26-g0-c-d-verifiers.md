# 2026-08-26 — G0-C/G0-D dedicated verifiers and failure semantics

## Scope

- Added dedicated read-only verifiers for Git-for-Windows/Git Bash, Windows normalized family, NVIDIA `nvidia-smi`, Visual Studio/vswhere + MSVC/Windows SDK, Codex CLI/Desktop, Supabase CLI, VS Code CLI, and .NET SDK/runtime lists.
- Removed `bash.exe` PATH alias interpretation as Git Bash and kept collector-process PATH diagnostics in `.local`.
- Added explicit observation verification states and reconciliation events for failed/timeout/unavailable checks. High-confidence absence checks retain records with `present: false` and `last_known`.
- Added focused parser, provider-shape, identity-split, Git Bash, and verification-state tests.

## Read-only host evidence

- Windows registry reported raw `Windows 10 Home` with build `26200`; normalized family is `Windows 11`.
- Git-for-Windows was verified at `D:\Git\Git`; authoritative Git Bash is `D:\Git\Git\bin\bash.exe`.
- NVIDIA `nvidia-smi` verified `NVIDIA GeForce RTX 3070 Laptop GPU`, driver `610.88`, and `8192 MiB` VRAM. CIM `AdapterRAM` is no longer used.
- Visual Studio Community 2022, MSVC `14.43.34808`, and Windows SDK `10.0.22621.0` were observed.
- Codex CLI, Codex Desktop Appx, and Supabase CLI were verified. A host VS Code CLI candidate was found at the known install path, but `code --version` failed; it remains a local candidate/unverified rather than canonical software. `.NET --version` reported no SDKs, while SDK/runtime list probes succeeded; the runtime presence is verified and SDK state is explicitly `absent`.

## Verification

- PowerShell parser check passed for all runtime, collection, reconciliation, and collector files.
- `tests/run-tests.ps1` passed, including dedicated verifier fixtures and failure/absence reconciliation fixtures.
- Quick collection completed with `partial` overall health because the required host-authoritative provider reported the VS Code CLI probe failure; optional NVIDIA/Visual Studio providers succeeded, and exact local diagnostics remain under `.local`.
- `sync.ps1 -Mode Quick -AllowDirty -NoPublish` reached reconciliation/render/validation without publishing. Validation still rejects historical canonical collection metadata and legacy project shape pollution; no canonical files were changed.
- Added fail-soft coverage for an unavailable optional `nvidia-smi` and a reconciliation guard preventing an `unverified` `present: false` observation from erasing a previously verified entity.
