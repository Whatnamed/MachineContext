# Export the actual, already-deployed user-global instruction files.
# Do not generate/merge rules, and do not modify any local agent configuration.
# Run from a locally synced E:\MachineContext checkout.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceCodex = Join-Path $HOME '.codex/AGENTS.md'
$sourceDsh = Join-Path $HOME '.dsh/AGENTS.md'
$targetDir = Join-Path $repo 'docs/global-agent-rules'
$required = @('## 沟通', '## 任务执行', '## 仓库状态', '## 测试与验证', '## Git 与开发环境', '## 完成与汇报')

foreach ($source in @($sourceCodex, $sourceDsh)) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing live global rule file: $source"
    }
    $raw = [System.IO.File]::ReadAllText($source, [System.Text.UTF8Encoding]::new($false, $true))
    foreach ($header in $required) {
        if (-not $raw.Contains($header)) {
            throw "Global rules seem incomplete: missing '$header' in $source. No files exported."
        }
    }
}
$dshText = [System.IO.File]::ReadAllText($sourceDsh, [System.Text.UTF8Encoding]::new($false, $true))
if (-not $dshText.Contains('## 联网检索')) {
    throw "DSH-specific '联网检索' section missing; refusing to replace repo copy."
}

[System.IO.Directory]::CreateDirectory($targetDir) | Out-Null
$copies = @(
    @{ Source = $sourceCodex; Target = (Join-Path $targetDir 'AGENTS.md') },
    @{ Source = $sourceDsh; Target = (Join-Path $targetDir 'DSH-AGENTS.md') }
)
foreach ($entry in $copies) {
    $bytes = [System.IO.File]::ReadAllBytes($entry.Source)
    [System.IO.File]::WriteAllBytes($entry.Target, $bytes)
    $sourceHash = (Get-FileHash -LiteralPath $entry.Source -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath $entry.Target -Algorithm SHA256).Hash
    if ($sourceHash -ne $targetHash) { throw "Copy verification failed: $($entry.Target)" }
    Write-Output ("{0}  {1} bytes  SHA256={2}" -f $entry.Target, $bytes.Length, $targetHash.Substring(0, 12))
}
Write-Output 'Exported complete, byte-identical current rules. Source files were not changed.'
Write-Output 'Review the generated files and git diff before explicitly committing/pushing to this PRIVATE repo.'
& git -C $repo status --short -- docs/global-agent-rules
