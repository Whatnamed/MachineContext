# 2026-08-26 — G0 correctness hardening

本次工作严格限定在 V1 G0-A/G0-B，未执行 Full Audit，也未改变本机软件、依赖或持久化环境。

- 修复 PowerShell 序列在 deterministic JSON 与 `Copy-McValue` 中被错误展开为对象 metadata 的问题；明确 Scalar/Mapping/Sequence 分类，并让不支持的对象类型 fail closed。
- validator 新增 software/project/machine/relationship contract checks，递归拒绝 `SyncRoot`、`IsFixedSize`、`IsReadOnly`、`LongLength`、`Rank`，并拒绝 canonical 中可归一化的 literal `%USERPROFILE%` 路径泄漏。
- 命令解析默认读取 `[Environment]::GetEnvironmentVariable('Path', 'Machine'/'User')`；当前 collector process 的 PATH 与 `Get-Command` 只用于 local diagnostics。
- shell provider 的 canonical output 标记为 `windows-host`；进程环境和进程解析写入 ignored `.local/staging/<run-id>/local-diagnostics.json`。
- tests 新增空/单/多数组、嵌套 project/software round-trip、canonical fixture validation 和 fake polluted process PATH fixture。

当前仓库中的既有 canonical 仍保留 G0 前生成的 .NET metadata 与一处 literal user path，因此 G0 阶段只记录 validator 证据；待 G1 执行 fresh audit 时统一重建 canonical。
