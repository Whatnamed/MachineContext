[CmdletBinding()]
param(
    [ValidateSet('Quick', 'Discover', 'Enrich', 'Full')]
    [string]$Mode = 'Quick',

    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [switch]$AllowDirty,

    [switch]$AllowRemoteDivergence,

    [switch]$NoPublish
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\runtime.ps1')
. (Join-Path $PSScriptRoot 'lib\collection.ps1')
. (Join-Path $PSScriptRoot 'lib\reconcile.ps1')
. (Join-Path $PSScriptRoot 'lib\validation.ps1')
. (Join-Path $PSScriptRoot 'lib\rendering.ps1')

function Get-McGitSafetyState {
    param(
        [Parameter(Mandatory)][string]$Root
    )

    $porcelain = @(& git.exe -C $Root status --porcelain 2>$null)
    $tracking = [string](& git.exe -C $Root rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null)
    $behind = 0
    $ahead = 0
    if (-not [string]::IsNullOrWhiteSpace($tracking)) {
        $counts = @(& git.exe -C $Root rev-list --left-right --count ("HEAD...{0}" -f $tracking) 2>$null)
        if ($counts.Count -gt 0) {
            $parts = ([string]$counts[0]).Trim() -split '\s+'
            if ($parts.Count -ge 2) {
                [int]::TryParse($parts[0], [ref]$ahead) | Out-Null
                [int]::TryParse($parts[1], [ref]$behind) | Out-Null
            }
        }
    }

    return [pscustomobject][ordered]@{
        dirty = ($porcelain.Count -gt 0)
        changed_paths = @($porcelain)
        tracking = $tracking
        ahead = $ahead
        behind = $behind
    }
}

function Publish-McAtomicFiles {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][object]$RunContext
    )

    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($source in @(Get-ChildItem -LiteralPath $RunContext.proposed_context -Recurse -File -ErrorAction Stop | Where-Object { $_.Extension -ieq '.json' -and $_.Name -ne '_template.json' })) {
        $relative = $source.FullName.Substring($RunContext.proposed_root.Length + 1)
        $target = Join-Path $RepoRoot $relative
        [void]$files.Add([pscustomobject]@{ source = $source.FullName; target = $target; delete = $false })
    }
    [void]$files.Add([pscustomobject]@{ source = $RunContext.proposed_current; target = Join-Path $RepoRoot 'CURRENT.md'; delete = $false })

    $repoFull = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path.TrimEnd('\')
    foreach ($relative in @($RunContext.proposed_deletions)) {
        if ([string]::IsNullOrWhiteSpace([string]$relative)) { continue }
        $relativePath = ([string]$relative).Replace('/', '\').TrimStart('\')
        if ([System.IO.Path]::IsPathRooted($relativePath)) { throw "Refusing to delete an absolute publish path: $relative" }
        $target = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $relativePath))
        if (-not $target.StartsWith($repoFull + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw "Refusing to delete a path outside the repository: $relative" }
        [void]$files.Add([pscustomobject]@{ source = $null; target = $target; relative = $relativePath; delete = $true })
    }

    $backupRoot = Join-Path $RunContext.run_root 'publish-backup'
    [void](New-Item -ItemType Directory -Path $backupRoot -Force)
    $published = [System.Collections.Generic.List[object]]::new()
    $temporary = [System.Collections.Generic.List[string]]::new()

    try {
        foreach ($file in @($files | Sort-Object target)) {
            $targetParent = Split-Path -Parent $file.target
            [void](New-Item -ItemType Directory -Path $targetParent -Force)
            $relativeTarget = $file.target.Substring($RepoRoot.Length + 1)
            $backupPath = Join-Path $backupRoot $relativeTarget
            $tempPath = "$($file.target).mc-$($RunContext.run_id).tmp"
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $backupPath) -Force)
            $hadBackup = Test-Path -LiteralPath $file.target -PathType Leaf
            if ($hadBackup) {
                Copy-Item -LiteralPath $file.target -Destination $backupPath -Force
            }
            if ($file.delete -eq $true) {
                if ($hadBackup) { Remove-Item -LiteralPath $file.target -Force }
                [void]$published.Add([pscustomobject]@{ target = $file.target; backup = $backupPath; had_backup = $hadBackup })
                continue
            }
            Copy-Item -LiteralPath $file.source -Destination $tempPath -Force
            [void]$temporary.Add($tempPath)
            Move-Item -LiteralPath $tempPath -Destination $file.target -Force
            [void]$published.Add([pscustomobject]@{ target = $file.target; backup = $backupPath; had_backup = $hadBackup })
        }
    }
    catch {
        foreach ($tempPath in @($temporary)) {
            if (Test-Path -LiteralPath $tempPath -PathType Leaf) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        }
        foreach ($file in @($published | Sort-Object target -Descending)) {
            if ($file.had_backup -and (Test-Path -LiteralPath $file.backup -PathType Leaf)) {
                Copy-Item -LiteralPath $file.backup -Destination $file.target -Force
            }
            elseif (Test-Path -LiteralPath $file.target -PathType Leaf) {
                Remove-Item -LiteralPath $file.target -Force -ErrorAction SilentlyContinue
            }
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $backupRoot -PathType Container) {
            Remove-Item -LiteralPath $backupRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    return @($files | ForEach-Object {
            $relative = $_.target.Substring($RepoRoot.Length + 1)
            if ($_.delete -eq $true) { "deleted:$relative" } else { $relative }
        } | Sort-Object)
}

$resolvedRoot = Get-McRepoRoot -Path $RepoRoot
$gitState = Get-McGitSafetyState -Root $resolvedRoot
if ($gitState.dirty -and -not $AllowDirty) {
    throw 'Working tree is dirty. Review or commit existing changes before publishing, or explicitly pass -AllowDirty.'
}
if ($gitState.behind -gt 0 -and -not $AllowRemoteDivergence) {
    throw ("Local branch is behind {0} by {1} commit(s); pull/reconcile explicitly before publishing." -f $gitState.tracking, $gitState.behind)
}

$run = New-McRunContext -RepoRoot $resolvedRoot -Mode $Mode
$collection = Invoke-McCollection -RunContext $run
$reconciled = Invoke-McReconciliation -RunContext $run -CollectionResult $collection
Invoke-McRender -RepoRoot $resolvedRoot -ContextRoot $run.proposed_context -OutputPath $run.proposed_current | Out-Null
$validation = Invoke-McValidation -RepoRoot $resolvedRoot -ContextRoot $run.proposed_context -CurrentPath $run.proposed_current
if (-not $validation.ok) {
    Write-McJson -Path (Join-Path $run.run_root 'validation.json') -InputObject $validation
    $validation | ConvertTo-Json -Depth 20
    throw 'Validation failed; canonical context was not published.'
}

$published = $false
$changedFiles = @()
if (-not $NoPublish) {
    $changedFiles = Publish-McAtomicFiles -RepoRoot $resolvedRoot -RunContext $run
    $published = $true
}

$after = Get-McGitSafetyState -Root $resolvedRoot
[pscustomobject][ordered]@{
    run_id = $run.run_id
    mode = $Mode
    overall_health = $collection.diagnostics.overall_health
    published = $published
    changed_files = @($changedFiles)
    candidate_count = $collection.candidates.Count
    provider_summary = ConvertTo-McPublishedProviderSummary -Providers $collection.diagnostics.providers
    git_status = $after.changed_paths
    validation = [pscustomobject][ordered]@{ ok = $validation.ok; warning_count = @($validation.warnings).Count }
} | ConvertTo-Json -Depth 20
