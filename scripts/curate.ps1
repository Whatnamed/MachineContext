[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [Parameter(Mandatory)]
    [string]$ConfirmationPath,

    [switch]$Apply,

    [switch]$AllowDirty
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'lib\runtime.ps1')
. (Join-Path $PSScriptRoot 'lib\reconcile.ps1')
. (Join-Path $PSScriptRoot 'lib\validation.ps1')
. (Join-Path $PSScriptRoot 'lib\rendering.ps1')
. (Join-Path $PSScriptRoot 'lib\curation.ps1')

$resolvedRoot = Get-McRepoRoot -Path $RepoRoot
$resolvedConfirmationPath = if ([System.IO.Path]::IsPathRooted($ConfirmationPath)) {
    [System.IO.Path]::GetFullPath($ConfirmationPath)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path $resolvedRoot $ConfirmationPath))
}

$plan = New-McCurationPlan -RepoRoot $resolvedRoot -ConfirmationPath $resolvedConfirmationPath
$result = [ordered]@{
    ok = $plan.ok
    read_only = (-not $Apply)
    applied = $false
    confirmation_path = $ConfirmationPath
    project_update_count = if ($plan.PSObject.Properties['project_update_count']) { $plan.project_update_count } else { 0 }
    software_update_count = if ($plan.PSObject.Properties['software_update_count']) { $plan.software_update_count } else { 0 }
    conventions_update = if ($plan.PSObject.Properties['conventions_update']) { $plan.conventions_update } else { $false }
    changed_files = @($plan.changes | ForEach-Object { $_.relative_path })
    errors = @($plan.errors)
}

if ($plan.ok -and $Apply) {
    $statusLines = @(git -C $resolvedRoot status --porcelain 2>$null)
    if ($statusLines.Count -gt 0 -and -not $AllowDirty) {
        $result.ok = $false
        $result.errors = @([pscustomobject][ordered]@{
                severity = 'error'
                code = 'curation_dirty_tree'
                message = 'Working tree is dirty. Review/commit existing changes or pass -AllowDirty explicitly.'
                path = $resolvedRoot
            })
    }
    else {
        $applied = Invoke-McCurationApply -Plan $plan -RepoRoot $resolvedRoot
        $result.applied = [bool]$applied.applied
        $result.changed_files = @($applied.changed_files)
        $result.validation = $applied.validation
        if (-not $applied.validation.ok) {
            $result.ok = $false
            $result.errors = @($applied.validation.errors)
        }
    }
}

Write-Output (ConvertTo-McJsonText -InputObject ([pscustomobject]$result) -Depth 30)
if (-not $result.ok) {
    exit 1
}
