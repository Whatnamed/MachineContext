Set-StrictMode -Version Latest

function New-McProviderPayload {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [ValidateSet('success', 'partial', 'unavailable', 'timed_out', 'failed')]
        [string]$Health = 'success',

        [int]$ResultCount = 0,
        [string[]]$Warnings = @(),
        [bool]$CoverageComplete = $false,
        [bool]$Optional = $false
    )

    return [pscustomobject][ordered]@{
        value             = $Value
        health            = $Health
        result_count      = $ResultCount
        warnings          = @($Warnings)
        coverage_complete = $CoverageComplete
        optional          = $Optional
    }
}

function Invoke-McSafeProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CollectionState,

        [Parameter(Mandatory)]
        [string]$Provider,

        [Parameter(Mandatory)]
        [scriptblock]$Action,

        [bool]$Optional = $false
    )

    $started = [System.Diagnostics.Stopwatch]::GetTimestamp()
    try {
        $raw = @(& $Action)
        $payload = if ($raw.Count -eq 0) { $null } elseif ($raw.Count -eq 1) { $raw[0] } else { $raw }

        if ($null -eq $payload -or $null -eq $payload.PSObject.Properties['health']) {
            $payload = New-McProviderPayload -Value $payload -ResultCount (@($payload).Count) -Optional $Optional
        }

        $duration = (([System.Diagnostics.Stopwatch]::GetTimestamp() - $started) * 1000.0) / [System.Diagnostics.Stopwatch]::Frequency
        $warnings = @($payload.warnings)
        foreach ($warning in $warnings) {
            Add-McDiagnosticWarning -Diagnostics $CollectionState.diagnostics -Message ("{0}: {1}" -f $Provider, $warning)
        }
        [void](Add-McProviderDiagnostic -Diagnostics $CollectionState.diagnostics -Provider $Provider -Health ([string]$payload.health) -DurationMs $duration -ResultCount ([int]$payload.result_count) -WarningCount $warnings.Count -CoverageComplete ([bool]$payload.coverage_complete) -Optional ([bool]$payload.optional))
        return $payload
    }
    catch {
        $duration = (([System.Diagnostics.Stopwatch]::GetTimestamp() - $started) * 1000.0) / [System.Diagnostics.Stopwatch]::Frequency
        Add-McDiagnosticError -Diagnostics $CollectionState.diagnostics -Message ("{0}: {1}" -f $Provider, $_.Exception.Message)
        [void](Add-McProviderDiagnostic -Diagnostics $CollectionState.diagnostics -Provider $Provider -Health 'failed' -DurationMs $duration -ResultCount 0 -WarningCount 1 -Message $_.Exception.Message -CoverageComplete $false -Optional $Optional)
        return (New-McProviderPayload -Value $null -Health 'failed' -Warnings @($_.Exception.Message) -Optional $Optional)
    }
}

function Add-McObservationListItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$List,

        [Parameter(Mandatory)]
        [object]$Item
    )

    [void]$List.Add($Item)
}

function Add-McCandidateListItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CollectionState,

        [Parameter(Mandatory)]
        [object]$Candidate
    )

    [void]$CollectionState.candidates.Add($Candidate)
}

function Get-McCollectionRootsFromManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $roots = [System.Collections.Generic.List[string]]::new()
    $conventionsPath = Join-Path $RepoRoot 'context\conventions.json'
    if (Test-Path -LiteralPath $conventionsPath -PathType Leaf) {
        try {
            $conventions = Read-McJson -Path $conventionsPath
            foreach ($root in @($conventions.directories.known_roots)) {
                $path = if ($root -is [string]) { $root } elseif ($null -ne $root.path) { [string]$root.path } else { $null }
                if (-not [string]::IsNullOrWhiteSpace($path)) {
                    $normalized = ConvertTo-McNormalizedPath -Path $path
                    if ($null -ne $normalized -and $roots.Add($normalized)) {
                    }
                }
            }
        }
        catch {
        }
    }

    return @($roots)
}

function New-McCollectionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RunContext
    )

    $observations = [ordered]@{
        schema_version = 1
        run_id         = $RunContext.run_id
        mode           = $RunContext.mode
        machine        = [ordered]@{}
        network        = [ordered]@{}
        software      = [ordered]@{
            development = [System.Collections.Generic.List[object]]::new()
            ai          = [System.Collections.Generic.List[object]]::new()
        }
        projects       = [System.Collections.Generic.List[object]]::new()
        relationships  = [System.Collections.Generic.List[object]]::new()
    }

    return [pscustomobject][ordered]@{
        run_context  = $RunContext
        diagnostics  = New-McDiagnosticsContext -Mode $RunContext.mode
        observations = $observations
        candidates   = [System.Collections.Generic.List[object]]::new()
    }
}

function Add-McModuleObservations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CollectionState,

        [Parameter(Mandatory)]
        [ValidateSet('development', 'ai')]
        [string]$Module,

        [AllowNull()]
        [object[]]$Entities
    )

    foreach ($entity in @($Entities)) {
        if ($null -ne $entity) {
            [void]$CollectionState.observations.software[$Module].Add($entity)
        }
    }
}

function Invoke-McCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RunContext
    )

    $state = New-McCollectionState -RunContext $RunContext
    $machine = [ordered]@{}

    $system = Invoke-McSafeProvider -CollectionState $state -Provider 'system-hardware-storage' -Action {
        Get-McSystemHardwareObservation
    }
    if ($null -ne $system.value) {
        foreach ($property in (Get-McPropertyEntries -InputObject $system.value)) {
            $machine[$property.Name] = $property.Value
        }
    }

    $shells = Invoke-McSafeProvider -CollectionState $state -Provider 'shells-path-resolution' -Action {
        Get-McShellObservation
    }
    if ($null -ne $shells.value) {
        foreach ($property in (Get-McPropertyEntries -InputObject $shells.value)) {
            $machine[$property.Name] = $property.Value
        }
    }

    $runtimes = Invoke-McSafeProvider -CollectionState $state -Provider 'runtimes-package-managers-toolchain' -Action {
        Get-McRuntimeToolObservations
    }
    if ($null -ne $runtimes.value) {
        Add-McModuleObservations -CollectionState $state -Module 'development' -Entities @($runtimes.value.entities)
        foreach ($candidate in @($runtimes.value.candidates)) {
            if ($null -ne $candidate) {
                Add-McCandidateListItem -CollectionState $state -Candidate $candidate
            }
        }
        foreach ($relationship in @($runtimes.value.relationships)) {
            if ($null -ne $relationship) {
                [void]$state.observations.relationships.Add($relationship)
            }
        }
    }

    $ai = Invoke-McSafeProvider -CollectionState $state -Provider 'ai-tooling' -Action {
        Get-McAiToolObservations -RepoRoot $RunContext.repo_root
    }
    if ($null -ne $ai.value) {
        Add-McModuleObservations -CollectionState $state -Module 'ai' -Entities @($ai.value.entities)
        foreach ($candidate in @($ai.value.candidates)) {
            if ($null -ne $candidate) {
                Add-McCandidateListItem -CollectionState $state -Candidate $candidate
            }
        }
        foreach ($relationship in @($ai.value.relationships)) {
            if ($null -ne $relationship) {
                [void]$state.observations.relationships.Add($relationship)
            }
        }
    }

    $network = Invoke-McSafeProvider -CollectionState $state -Provider 'network-local-services' -Action {
        Get-McNetworkObservation
    }
    if ($null -ne $network.value) {
        foreach ($property in (Get-McPropertyEntries -InputObject $network.value)) {
            $state.observations.network[$property.Name] = $property.Value
        }
    }

    $discoveryMode = $RunContext.mode -in @('Discover', 'Full')
    if ($discoveryMode) {
        $registry = Invoke-McSafeProvider -CollectionState $state -Provider 'registry-uninstall' -Action {
            Get-McRegistryAppCandidates
        }
        foreach ($candidate in @($registry.value)) {
            if ($null -ne $candidate) {
                Add-McCandidateListItem -CollectionState $state -Candidate $candidate
            }
        }

        $winget = Invoke-McSafeProvider -CollectionState $state -Provider 'winget-export' -Action {
            Get-McWingetCandidates -RawDirectory (Join-Path $RunContext.run_root 'raw')
        } -Optional $true
        foreach ($candidate in @($winget.value)) {
            if ($null -ne $candidate) {
                Add-McCandidateListItem -CollectionState $state -Candidate $candidate
            }
        }

        $projects = Invoke-McSafeProvider -CollectionState $state -Provider 'project-fingerprints' -Action {
            Get-McProjectCandidates -RepoRoot $RunContext.repo_root
        }
        foreach ($candidate in @($projects.value)) {
            if ($null -ne $candidate) {
                [void]$state.observations.projects.Add($candidate)
                Add-McCandidateListItem -CollectionState $state -Candidate $candidate
            }
        }

        $everything = Invoke-McSafeProvider -CollectionState $state -Provider 'everything-index' -Action {
            Get-McEverythingCandidates -RepoRoot $RunContext.repo_root
        } -Optional $true
        foreach ($candidate in @($everything.value)) {
            if ($null -ne $candidate) {
                Add-McCandidateListItem -CollectionState $state -Candidate $candidate
            }
        }
    }

    $state.observations.machine = [pscustomobject]$machine
    $state.diagnostics.finished_at = (Get-Date).ToUniversalTime().ToString('o')
    $state.diagnostics.overall_health = Get-McOverallProviderHealth -Providers $state.diagnostics.providers
    Set-McDiagnosticCount -Diagnostics $state.diagnostics -Name 'candidate_count' -Value $state.candidates.Count
    Set-McDiagnosticCount -Diagnostics $state.diagnostics -Name 'project_count' -Value $state.observations.projects.Count
    Set-McDiagnosticCount -Diagnostics $state.diagnostics -Name 'development_observation_count' -Value $state.observations.software.development.Count
    Set-McDiagnosticCount -Diagnostics $state.diagnostics -Name 'ai_observation_count' -Value $state.observations.software.ai.Count

    $observations = [pscustomobject]$state.observations
    Write-McLocalRunArtifacts -RunContext $RunContext -Observations $observations -Candidates @([pscustomobject][ordered]@{
            schema_version = 1
            run_id         = $RunContext.run_id
            mode           = $RunContext.mode
            candidates     = $state.candidates
        }) -Diagnostics $state.diagnostics
    Write-McLocalState -RunContext $RunContext -Diagnostics $state.diagnostics

    return [pscustomobject][ordered]@{
        run_context = $RunContext
        observations = $observations
        candidates = @($state.candidates)
        diagnostics = $state.diagnostics
    }
}

# Domain collectors are deliberately separate files. They are loaded after the
# shared collection helpers so the entry points remain dependency-free.
$collectorRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'collectors'
foreach ($collector in @(
        'system.ps1',
        'shells.ps1',
        'runtimes.ps1',
        'ai-tools.ps1',
        'network.ps1',
        'registry-apps.ps1',
        'projects.ps1',
        'discovery-everything.ps1'
    )) {
    $collectorPath = Join-Path $collectorRoot $collector
    if (Test-Path -LiteralPath $collectorPath -PathType Leaf) {
        . $collectorPath
    }
}
