[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$ContextRoot,

    [string]$CurrentPath
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\runtime.ps1')
. (Join-Path $PSScriptRoot 'lib\validation.ps1')

$resolvedRoot = Get-McRepoRoot -Path $RepoRoot
if ([string]::IsNullOrWhiteSpace($ContextRoot)) { $ContextRoot = Join-Path $resolvedRoot 'context' }
if ([string]::IsNullOrWhiteSpace($CurrentPath)) { $CurrentPath = Join-Path $resolvedRoot 'CURRENT.md' }

$result = Invoke-McValidation -RepoRoot $resolvedRoot -ContextRoot $ContextRoot -CurrentPath $CurrentPath
$result | ConvertTo-Json -Depth 20
if (-not $result.ok) {
    exit 1
}
