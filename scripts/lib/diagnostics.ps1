Set-StrictMode -Version Latest

$script:McProviderHealthValues = @('success', 'partial', 'unavailable', 'timed_out', 'failed')

function New-McDiagnosticsContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Quick', 'Discover', 'Enrich', 'Full')]
        [string]$Mode
    )

    return [pscustomobject][ordered]@{
        schema_version = 1
        mode           = $Mode
        started_at     = (Get-Date).ToUniversalTime().ToString('o')
        finished_at    = $null
        overall_health = $null
        providers      = [System.Collections.Generic.List[object]]::new()
        warnings       = [System.Collections.Generic.List[string]]::new()
        errors         = [System.Collections.Generic.List[string]]::new()
        counts         = [ordered]@{}
    }
}

function Add-McProviderDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Diagnostics,

        [Parameter(Mandatory)]
        [string]$Provider,

        [Parameter(Mandatory)]
        [ValidateSet('success', 'partial', 'unavailable', 'timed_out', 'failed')]
        [string]$Health,

        [double]$DurationMs = 0,
        [int]$ResultCount = 0,
        [int]$WarningCount = 0,
        [string]$Message,
        [bool]$CoverageComplete = $false,
        [bool]$Optional = $false
    )

    $entry = [ordered]@{
        provider          = $Provider
        health            = $Health
        duration_ms       = [math]::Round($DurationMs, 2)
        result_count      = $ResultCount
        warning_count     = $WarningCount
        coverage_complete = $CoverageComplete
        optional          = $Optional
    }
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $entry.message = ConvertTo-McSafeDiagnosticText -Text $Message
    }

    [void]$Diagnostics.providers.Add([pscustomobject]$entry)
    return [pscustomobject]$entry
}

function Add-McDiagnosticWarning {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Diagnostics,

        [Parameter(Mandatory)]
        [string]$Message
    )

    [void]$Diagnostics.warnings.Add((ConvertTo-McSafeDiagnosticText -Text $Message))
}

function Add-McDiagnosticError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Diagnostics,

        [Parameter(Mandatory)]
        [string]$Message
    )

    [void]$Diagnostics.errors.Add((ConvertTo-McSafeDiagnosticText -Text $Message))
}

function Set-McDiagnosticCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Diagnostics,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [int]$Value
    )

    $Diagnostics.counts[$Name] = $Value
}

function Get-McOverallProviderHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Providers
    )

    # Optional accelerators/enrichment providers keep their exact health in local
    # diagnostics, but must not turn an otherwise usable audit into a whole-run
    # failure. Required providers still determine the aggregate health.
    $effectiveProviders = @($Providers | Where-Object { -not ($_.optional -eq $true) })
    $healths = @($effectiveProviders | ForEach-Object { [string]$_.health })
    if ($healths.Count -eq 0) {
        return 'unavailable'
    }
    if ($healths -contains 'failed') {
        return 'failed'
    }
    if ($healths -contains 'timed_out') {
        return 'timed_out'
    }
    if ($healths -contains 'partial') {
        return 'partial'
    }
    if ($healths -contains 'unavailable') {
        return 'partial'
    }

    return 'success'
}

function ConvertTo-McPublishedProviderSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Providers
    )

    $items = foreach ($provider in @($Providers | Sort-Object provider)) {
        [pscustomobject][ordered]@{
            provider = [string]$provider.provider
            health   = [string]$provider.health
        }
    }

    return @($items)
}
