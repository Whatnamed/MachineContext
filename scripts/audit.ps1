[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [switch]$RequireVerified
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'lib\runtime.ps1')
. (Join-Path $PSScriptRoot 'lib\reconcile.ps1')
. (Join-Path $PSScriptRoot 'lib\audit.ps1')

$review = Get-McAuditClosureReview -RepoRoot $RepoRoot
if ($RequireVerified -and $review.closure.state -ne 'verified') {
    $review.ok = $false
    $review.errors = @($review.errors) + @([pscustomobject][ordered]@{
            severity = 'error'
            code = 'audit_closure_not_verified'
            message = 'Audit closure is not verified.'
            path = '.local/audit-closure.json'
        })
}

Write-Output (ConvertTo-McJsonText -InputObject $review -Depth 30)
if (-not $review.ok) {
    exit 1
}
