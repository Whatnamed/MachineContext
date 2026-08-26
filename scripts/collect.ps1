[CmdletBinding()]
param(
    [ValidateSet('Quick', 'Discover', 'Enrich', 'Full')]
    [string]$Mode = 'Quick',

    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\runtime.ps1')
. (Join-Path $PSScriptRoot 'lib\collection.ps1')

$resolvedRoot = Get-McRepoRoot -Path $RepoRoot
$run = New-McRunContext -RepoRoot $resolvedRoot -Mode $Mode
$result = Invoke-McCollection -RunContext $run

[pscustomobject][ordered]@{
    run_id = $run.run_id
    mode = $Mode
    overall_health = $result.diagnostics.overall_health
    observations_path = ConvertTo-McNormalizedPath -Path $run.observations_path
    candidates_path = ConvertTo-McNormalizedPath -Path $run.candidates_path
    diagnostics_path = ConvertTo-McNormalizedPath -Path $run.diagnostics_path
    local_diagnostics_path = ConvertTo-McNormalizedPath -Path $run.local_diagnostics_path
    candidate_count = $result.candidates.Count
} | ConvertTo-Json -Depth 10
