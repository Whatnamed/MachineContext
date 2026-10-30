# 2026-10-30 Read-only inventory sync and PowerShell startup diagnosis

Follow-up: The user subsequently authorized upgrading PowerShell only. The [7.6.9 upgrade and startup verification](2026-10-30-pwsh-769-upgrade.md) supersede the unresolved status below; this entry preserves the preceding read-only session.

Scope: Refresh the existing Quick inventory and publish repository records. The user explicitly excluded software installation/upgrades and machine configuration changes. No collector implementation, collection scope, PATH, registry, proxy, or PowerShell settings were changed.

## Observed changes

- PowerShell at `%PROGRAMFILES%\PowerShell\7\pwsh.exe`: 7.6.7; the Codex-bundled 7.6.5 runtime is not the Windows host shell.
- Agy: 1.3.6; DSH CLI: 0.2.1-rc.2; Codex Desktop: 26.1027.3384.0, including its package path and configured MCP runtime paths.
- DSH Desktop: 0.2.1-rc.2, confirmed by its existing HKCU uninstall identity and executable FileVersion. This supplemental entity is not refreshed by routine collection, so its observed version was corrected separately. Its old update-feed note was explicitly dated as historical evidence; no update-feed freshness claim was added.
- Codex and DSH configured reasoning effort: high. These are observed local settings, not settings changed during this session.
- Refresh existing persistent PATH observations and disk free-space records without changing either source.

## PowerShell diagnosis (not repaired)

The supplied startup crash contains `UpdatesNotification.ShowUpdateNotification`, `String.PadRight`, and `totalWidth = -17`. Reading the installed 7.6.7 zh-Hans resource produces line lengths 38 and 58, so the shipped formatting calculation is `38 - 58 + 3 = -17`.

The local update-notification cache contains `update1_v7.6.8_2026-10-22`. The 7.6.7 source delays notification for seven days, consistent with this crash becoming eligible on 2026-10-29 at 08:00 Asia/Shanghai. This establishes a matching trigger from local evidence; no interactive crash was deliberately reproduced.

Upstream [issue #28131](https://github.com/PowerShell/PowerShell/issues/28131) and [7.6.7 source](https://github.com/PowerShell/PowerShell/blob/v7.6.7/src/Microsoft.PowerShell.ConsoleHost/host/msh/UpdatesNotification.cs) match the failure. [7.6.8](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.8) removed update notifications through [PR #28242](https://github.com/PowerShell/PowerShell/pull/28242); 7.6.9 was the latest stable release checked during this session. Upgrading, `-NoLogo`, or setting `POWERSHELL_UPDATECHECK=Off` before startup were discussed but not applied. PowerShell remains at 7.6.7 with the startup issue unresolved.

## Verification

- First Quick sync: all ten providers successful; validation returned zero errors, warnings, and findings.
- Repeated Quick syncs also returned ten successful providers and zero validation findings. The first repeat observed a real 256 MiB decrease in the D: free-space bucket; that observation was incorporated. The final dry-run proposal (`20261030-064434851-c073eb7a`) matched all 28 canonical JSON files and generated `CURRENT.md` byte-for-byte, with no further semantic drift or evidence accumulation.
- Added context lines passed the secret-keyword and credential-pattern privacy sweep. Final standalone validation and Git whitespace checks passed before commit. Raw probes and the one-time DSH refresh script remain under ignored `.local/`.
- No collector or production script changed, so the data/document-only refresh did not require the implementation test suite.
- Existing overall audit state remains partial; a successful Quick refresh does not close older audit unknowns or reverify the complete supplemental software inventory.
