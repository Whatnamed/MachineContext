[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot),

    [switch]$RequireClosed
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'lib\runtime.ps1')
. (Join-Path $PSScriptRoot 'lib\reconcile.ps1')
. (Join-Path $PSScriptRoot 'lib\audit.ps1')
. (Join-Path $PSScriptRoot 'lib\review.ps1')

$closure = Get-McAuditClosureReview -RepoRoot $RepoRoot
$semantic = Get-McSemanticReview -RepoRoot $RepoRoot
$gateErrors = [System.Collections.Generic.List[object]]::new()

if ($RequireClosed) {
    if ($closure.closure.state -ne 'verified') {
        [void]$gateErrors.Add([pscustomobject][ordered]@{
                severity = 'error'
                code = 'review_closure_not_verified'
                message = 'Initial audit closure is not verified.'
                path = '.local/audit-closure.json'
            })
    }
    if ($semantic.requires_confirmation) {
        [void]$gateErrors.Add([pscustomobject][ordered]@{
                severity = 'error'
                code = 'review_semantics_require_confirmation'
                message = 'G2 semantic review still contains confirmation-gated items.'
                path = '.local/g2-semantic-review.json'
            })
    }
}

$result = [pscustomobject][ordered]@{
    ok = ($closure.ok -and $semantic.ok -and $gateErrors.Count -eq 0)
    read_only = $true
    requires_confirmation = $semantic.requires_confirmation
    initial_audit_review = $closure
    semantic_review = $semantic
    errors = @($gateErrors.ToArray())
}

Write-Output (ConvertTo-McJsonText -InputObject $result -Depth 30)
if (-not $result.ok) {
    exit 1
}
