# Visual Studio Native Desktop verifier

- Added a dedicated `vswhere -requires Microsoft.VisualStudio.Workload.NativeDesktop` probe to the existing Visual Studio/MSVC/Windows SDK collector.
- A successful query with matching installations is `verified-present`; a successful empty result is `verified-absent`; timeout, failure, or malformed output remains `unverified` and cannot become an absence claim.
- The internal validation contract checks the workload ID, state/path combination, and rejects an unsafe `present: false` on an unverified or stale result.
- The verifier is read-only and does not install workloads or change Visual Studio state.
