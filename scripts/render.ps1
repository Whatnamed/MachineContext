[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string]$ContextRoot,

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\runtime.ps1')
. (Join-Path $PSScriptRoot 'lib\rendering.ps1')

$resolvedRoot = Get-McRepoRoot -Path $RepoRoot
if ([string]::IsNullOrWhiteSpace($ContextRoot)) { $ContextRoot = Join-Path $resolvedRoot 'context' }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $resolvedRoot 'CURRENT.md' }

Invoke-McRender -RepoRoot $resolvedRoot -ContextRoot $ContextRoot -OutputPath $OutputPath | Write-Output
