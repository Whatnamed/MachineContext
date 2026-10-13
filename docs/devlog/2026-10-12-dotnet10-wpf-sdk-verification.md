# .NET 10 SDK and WPF compilation verification — 2026-10-12

The existing project-local x64 SDK is usable. No SDK was downloaded, installed,
copied or moved. The Windows-host `dotnet` entry describes the runtime-only
system installation; it does not imply that all project-local SDKs are absent.

## Read-only discovery

| SDK root | Observed state |
| --- | --- |
| `E:\CS2MOD\tooling\dotnet` | Directory absent |
| `E:\Projects\CS2-Local-Kit\CS2-Local-Kit\temp\tooling\dotnet` | SDK `10.0.401`, x64 host `10.0.12`, WindowsDesktop reference pack/runtime `10.0.12`; selected for compilation |
| `E:\Projects\CS2-Local-Kit\wt-14188-recovery\temp\tooling\dotnet` | SDK `10.0.401`, x64 host `10.0.12`, WindowsDesktop reference pack/runtime `10.0.12`; `--info` and reference files verified |
| `E:\Projects\CS2-Local-Kit\wt-compat-20261009\temp\tooling\dotnet` | Directory absent |
| `E:\Projects\CS2-Local-Kit\wt-startup-repair\temp\tooling\dotnet` | Directory absent |
| `E:\Dev\dotnet` | Directory absent; no new installation needed |
| `%PROGRAMFILES%\dotnet` | `--list-sdks` succeeds with no SDK entries |

The existing `scripts/controller/Publish-Controller.ps1` resolves an explicit
`-DotNetExe` first, otherwise current-worktree `temp\tooling\dotnet\dotnet.exe`,
then `E:\CS2MOD\tooling\dotnet\dotnet.exe`, then PATH. It was read, not executed
or edited. The SDK was invoked by absolute path from a verification directory
outside production workspaces.

Both local reference packs contain `PresentationFramework.dll` and
`PresentationCore.dll`. `Microsoft.NET.Sdk.WindowsDesktop/Sdk/Sdk.props` exists.
The two `PresentationFramework.dll` reference files have the same SHA256:
`62074ebdad60954ac4cfdbc06c4bb9cdc913d34ad0d6c0c65daac20c12f56eaa`.

## Minimal WPF verification

Project: `E:\Dev\validation\dotnet10-wpf-20261012\WpfSdkSmoke.csproj`.
It uses `Microsoft.NET.Sdk`, `net10.0-windows`, `UseWPF=true`, and actual
`App.xaml`/`MainWindow.xaml` with code behind. `global.json` pins SDK `10.0.401`
with roll forward disabled and prerelease SDKs disallowed.

```powershell
pwsh -NoProfile -File 'E:\Dev\validation\dotnet10-wpf-20261012\verify.ps1'
```

The script uses the existing primary SDK and runs:

```text
dotnet restore WpfSdkSmoke.csproj --configfile NuGet.Config --packages <project-local-cache> --disable-parallel --nologo -v minimal
dotnet build WpfSdkSmoke.csproj --no-restore -c Release --disable-build-servers --nologo -p:UseSharedCompilation=false -v minimal
```

`NuGet.Config` clears every package source; `NuGetAudit` is disabled for this
package-free verification project. Restore uses bundled reference packs.
CLI home and package caches are confined to the verification directory;
telemetry, workload updates and build servers are disabled for the child
process. No persistent environment settings were changed.

Verified at `2026-10-12T00:20:25.4623292Z`:

- restore exit `0`;
- Release build exit `0`, zero warnings and zero errors;
- compiled assembly `bin\Release\net10.0-windows\WpfSdkSmoke.dll`;
- actual XAML output `obj\Release\net10.0-windows\MainWindow.baml` and
  generated `MainWindow.g.cs`;
- assembly SHA256 `31370b8b3dea29eadee1031141e19012af43411f040c1f7a6f5c726476dc9724`.

Evidence remains under
`E:\Dev\validation\dotnet10-wpf-20261012\evidence\`:
`dotnet-info.txt`, `restore.log`, `build.log`, `verification.json`.
This verifies restore and WPF compilation. The GUI was not launched.
The alternative SDK was inspected but was not used for a second build.

## MachineContext update and scope

Added the separate `dotnet-sdk` software record with `project-local` scope,
primary/alternative paths, targeting pack, runtime and WPF compilation evidence.
It is supplemental inventory refreshed by explicit targeted verification;
routine host discovery still concerns the system installation. The existing
`dotnet` runtime record retains its host executable, runtime list and empty SDK
list, with its note narrowed to the system host. `CURRENT.md` is regenerated
from canonical JSON and now includes the usable SDK path.

The proposal passed the existing schema/reference/privacy validator with no
errors, warnings or findings before publication. No collection logic or test
code changed; no routine sync, network collector or security probe ran.
The broad provider verification timestamp was not refreshed by this scoped check.

CS2 and Morpho production sources were left unchanged. AgentBench's
`ISOLATION_RESEARCH_SUSPENDED=True` remains in force. No task admission state,
oracle, model evaluation or formal benchmark was changed or started.
