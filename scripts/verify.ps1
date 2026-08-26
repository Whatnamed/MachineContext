[CmdletBinding()]
param(
    [ValidateSet('Quick', 'Discover', 'Enrich', 'Full')]
    [string]$Mode = 'Quick',

    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [string[]]$Provider
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\runtime.ps1')
. (Join-Path $PSScriptRoot 'lib\collection.ps1')

$resolvedRoot = Get-McRepoRoot -Path $RepoRoot
$run = New-McRunContext -RepoRoot $resolvedRoot -Mode $Mode
$result = Invoke-McCollection -RunContext $run
$providers = if ($Provider.Count -gt 0) { @($result.diagnostics.providers | Where-Object provider -in $Provider) } else { @($result.diagnostics.providers) }

[pscustomobject][ordered]@{
    run_id = $run.run_id
    mode = $Mode
    overall_health = Get-McOverallProviderHealth -Providers $providers
    providers = $providers
    note = 'Verification is read-only; canonical context was not modified.'
} | ConvertTo-Json -Depth 20
