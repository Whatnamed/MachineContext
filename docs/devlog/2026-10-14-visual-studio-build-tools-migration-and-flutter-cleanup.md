# Devlog — 2026-10-14 Visual Studio Build Tools migration and Flutter cleanup

Scope: Retire the unused Visual Studio Community 2022 full IDE and Unity workloads, migrate to official standalone Visual Studio Build Tools 2022 located at `E:\Dev\BuildTools`, retire the obsolete Flutter/Dart development environment, clean up package download caches, and verify complete native Windows compilation capabilities for both active Tauri v2 desktop projects (`AgentBench` and `ProxyLens`) across baseline, isolated target, and post-uninstallation stages.

---

## 1. Summary of Changes and Toolchain Transitions

| Component | Before State | Action Taken | After State | Verified Evidence |
| --- | --- | --- | --- | --- |
| **Visual Studio IDE** | Visual Studio Community 2022 v17.13.5 (`17.13.35919.96`) at `D:\Visual Studio\product` (~5.25 GB) | Exported `.vsconfig` backup, then uninstalled via official installer | **Completely Removed** | Directory `D:\Visual Studio\product` removed; `vswhere` reports 0 IDE instances |
| **C++ Build Tools** | Part of VS Community at `D:\Visual Studio\product\VC\Tools\MSVC\14.43.34808` | Installed standalone Visual Studio Build Tools 2022 v17.14.42 (`17.14.37806.7`) at `E:\Dev\BuildTools` (~3.35 GB) | **Standalone Build Tools 2022** with MSVC v143 `14.44.35207` | `vswhere -products *` detects instance `832267a8`; `cl.exe` / `link.exe` resolved directly from `E:\Dev\BuildTools` |
| **Windows SDK** | Windows SDK `10.0.22621.0` in `D:\Windows Kits\10` (~2.25 GB) | Preserved existing `D:\Windows Kits\10` roots; Build Tools registered Windows 11 SDK `10.0.26100.0` matching OS build | **Windows SDK 10.0.26100.0** at `D:\Windows Kits\10` | Registry `KitsRoot10` = `D:\Windows Kits\10\`; `Include` & `Lib` verified present |
| **VS Installer Cache** | `D:\Visual Studio\huancun` (~2.14 GB) | Managed via installer during Community uninstallation | **Cleaned to 39 MB** metadata | Installer automatically removed unneeded package payloads; no manual deletion required |
| **Flutter SDK** | Flutter 3.41.9 / Dart 3.11.5 at `E:\Dev\flutter` (~2.91 GB) | Removed `E:\dev\flutter\bin` from User PATH; deleted SDK directory | **Completely Removed** | `Get-Command flutter` / `dart` fails in fresh shell; PATH cleaned |
| **Flutter Zip & Temp** | `E:\Dev\flutter_sdk.zip` (~1.71 GB) + temp logs | Cleaned installer zip and diagnostic txt files | **Cleaned** | Free space recovered on E: drive |
| **Pub Cache** | `%LOCALAPPDATA%\Pub\Cache` (~84 MB) | Removed user-level Pub cache and `.dartServer` | **Cleaned** | `%LOCALAPPDATA%\Pub` removed |

---

## 2. Project Verification Pipeline & Native Build Evidence

Both active Tauri v2 desktop projects were verified across multiple phases:
1. **Baseline Phase** (with old VS Community): verified initial native compile passes.
2. **Isolated Build Phase** (with new Build Tools alongside old VS): verified that `find-msvc-tools` / `cc` resolved MSVC from `E:\Dev\BuildTools` and built into isolated `$env:CARGO_TARGET_DIR = target_isolated` without cached artifacts.
3. **Post-Uninstallation Phase** (after old VS Community was cleanly removed): verified native compilation succeeded with zero reliance on old paths.

### A. Compiler Resolution Evidence
Probed via standard `cc` crate (`find-msvc-tools` + `vswhom`):
```
RESOLVED_COMPILER_PATH = "E:\\Dev\\BuildTools\\VC\\Tools\\MSVC\\14.44.35207\\bin\\HostX64\\x64\\cl.exe"
```
Resolved compiler banner:
`Microsoft (R) C/C++ Optimizing Compiler Version 19.44.35229 for x64`

### B. AgentBench Desktop App (`Whatnamed/AgentBench` branch `feat/desktop-ui-foundation`)
- **Location**: `E:\AgentBench\worktrees\desktop-ui-foundation\app`
- **Stack**: Windows Tauri v2 + React 19 + TypeScript + Vite
- **Build Command**: `npm.cmd run tauri -- build --no-bundle`
- **Isolated Target Build**:
  - Target: `src-tauri\target_isolated\release\agentbench-desktop.exe`
  - Duration: 2m 48s
  - File Size: 26,085,376 bytes
- **Post-Uninstallation Verification**:
  - Target: `src-tauri\target\release\agentbench-desktop.exe`
  - Completed: 2026-10-14 21:46:08
  - SHA256: `56B84F99B6BACA29382463AC31875F0AF4E00B0E4534D4E7FD3B7EF1B4638155`
  - Result: Native binary links and executes cleanly.

### C. ProxyLens Desktop App (`Whatnamed/ProxyLens`)
- **Location**: `E:\AgentBench\references\ProxyLens\ui`
- **Stack**: Windows Tauri v2 + React + Go sidecars (`proxylens-query-api`, `proxylens-runtime`, `proxylens-supervisor`)
- **Sidecar Build Command**: `npm.cmd run sidecar:build` (compiled 3 Go binaries for `x86_64-pc-windows-msvc`)
- **App Build Command**: `npm.cmd run tauri -- build --no-bundle`
- **Isolated Target Build**:
  - Target: `src-tauri\target_isolated\release\proxylens-desktop.exe`
  - Duration: 2m 30s
  - File Size: 28,562,944 bytes
- **Post-Uninstallation Verification**:
  - Target: `src-tauri\target\release\proxylens-desktop.exe`
  - Completed: 2026-10-14 21:47:20
  - SHA256: `2ED6569D520A0E747B331C77A81D772F852C3FCB15969335105CD1167C68560F`
  - Result: Native binary links and executes cleanly.

---

## 3. Storage Footprint Comparison

| Drive | Initial Free Space | Final Free Space | Net Space Reclaimed | Notes |
| --- | --- | --- | --- | --- |
| **C:** | 17.41 GB | **17.88 GB** | **+0.47 GB** | Cleaned Pub Cache and installer temp files |
| **D:** | 53.07 GB | **60.82 GB** | **+7.75 GB** | Uninstalled VS Community IDE (~5.25 GB) and installer package cache (~2.10 GB) |
| **E:** | 152.47 GB | **152.11 GB** | **-0.36 GB** | Installed standalone Build Tools (+3.35 GB) while freeing Flutter SDK & zip (-4.62 GB) |

*Cumulative D-drive recovery*: Free space increased from initial cleanup baseline of 9.61 GB to **60.82 GB** (total gain > 51.2 GB).

---

## 4. Preservation & Recovery Guidance

### Future Re-installation / Recovery of Visual Studio Community 2022
The exact configuration manifest of the previous installation is preserved at:
`docs/assets/toolchain-migration/vs_community_backup.vsconfig`

To restore the full IDE with exact workloads if coursework or Unity C# script debugging is ever needed again:
```powershell
vs_Community.exe --config "E:\MachineContext\docs\assets\toolchain-migration\vs_community_backup.vsconfig" --installPath "D:\Visual Studio\product" --passive
```

### Standalone Build Tools Configuration
The installed Build Tools component manifest is archived at:
`docs/assets/toolchain-migration/vs_buildtools_installed.vsconfig`
Contains `Microsoft.VisualStudio.Workload.VCTools`, `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`, `Microsoft.VisualStudio.Component.Windows11SDK.26100`, CMake, MSBuild, and vcpkg.
