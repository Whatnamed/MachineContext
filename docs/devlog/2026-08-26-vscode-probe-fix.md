# 2026-08-26 — repair the Windows `.cmd` probe path

## Finding

The machine had a real VS Code CLI at `D:\VSCode\Microsoft VS Code\bin\code.cmd`, and invoking that file directly with `--version` returned `1.134.0`. The shared probe nevertheless reported failure because it put the `/c` command string into `ProcessStartInfo.ArgumentList`; .NET escaped the embedded quotes with backslashes, which `cmd.exe` treated as part of the command name.

## Change

For explicitly selected `.cmd`/`.bat` probes, the launcher remains the fixed Windows `cmd.exe`, but the composed `/c` invocation is passed through the raw `Arguments` property. Normal executable and PowerShell probes continue to use argument lists. A tracked fixture with a path containing spaces now covers the command-script branch.

## Evidence

- `759dfdb fix: repair cmd script probe invocation` contains the implementation and fixture test.
- Quick collection `20260826-075426921-0ae416b3` verified VS Code `1.134.0` and changed host-authoritative-tools to `success`.
- Full publish `20260826-075631878-7d34ecb5` added only the verified `code` entity plus expected status/CURRENT changes.
- Full repeat `20260826-075731182-71b6dc04` was byte-identical; subsequent Quick runs `20260826-075824435-99551891` and `20260826-075849110-479a6116` had no canonical semantic drift.
