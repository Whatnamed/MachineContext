# 2026-08-26 — Non-authoritative pnpm store evidence

## Scope

The persistent host verifier still finds no `pnpm` executable, while a read-only allowlisted check finds `%LOCALAPPDATA%\pnpm\store`. This is useful audit evidence but cannot prove that the CLI is installed, usable, or absent.

The runtimes provider now keeps normalized known-path checks, persistent candidate resolution, store existence, and an explicit `store_is_not_cli_proof` marker under ignored `.local` diagnostics. No command was installed or executed through Corepack, no cache/store was changed, and canonical `pnpm` remains `unverified`.

## Verification

- Added a fixture for store presence plus a non-executable `pnpm.cmd` path check; the fixture never leaves `.local`.
- All 21 tests pass after the change.
- The next Full no-publish run must show this evidence only in local diagnostics and produce no canonical semantic diff.
