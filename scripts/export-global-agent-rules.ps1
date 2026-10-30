# Export the actually deployed personal global rules, without changing agent settings.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceCodex = Join-Path $HOME '.codex/AGENTS.md'
$sourceDsh = Join-Path $HOME '.dsh/AGENTS.md'
$targetDir = Join-Path $repo 'docs/global-agent-rules'
$required = @('## 沟通', '## 任务执行', '## 测试与验证', '## 完成与汇报')

foreach ($source in @($sourceCodex, $sourceDsh)) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Missing live global rule file: $source"
    }
    $raw = [System.IO.File]::ReadAllText($source, [System.Text.UTF8Encoding]::new($false, $true))
    foreach ($header in $required) {
        if (-not $raw.Contains($header)) {
            throw "Incomplete global rules: missing '$header' in $source; no files exported."
        }
    }
    if ($raw -notmatch '(?m)^## (仓库状态|仓库与本机环境)\s*$') {
        throw "Missing repository context chapter in $source."
    }
    if ($raw -notmatch '(?m)^## (Git|Git 与开发环境)\s*$') {
        throw "Missing Git chapter in $source."
    }
}
$dshText = [System.IO.File]::ReadAllText($sourceDsh, [System.Text.UTF8Encoding]::new($false, $true))
if (-not $dshText.Contains('## 联网检索')) {
    throw "DSH-specific 联网检索 section missing; no files exported."
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
Write-Output 'Exported current, byte-identical global rules. Source files were not modified.'
Write-Output 'Review generated content before committing or pushing to this PRIVATE repo.'
& git -C $repo status --short -- docs/global-agent-rules
