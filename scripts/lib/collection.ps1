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
        [bool]$Optional = $false,

        [AllowNull()]
        [object]$Local,

        [AllowNull()]
        [object[]]$VerificationEvents = @()
    )

    return [pscustomobject][ordered]@{
        value             = $Value
        health            = $Health
        result_count      = $ResultCount
        warnings          = @($Warnings)
        coverage_complete = $CoverageComplete
        optional          = $Optional
        local             = $Local
        verification_events = @($VerificationEvents)
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
        foreach ($event in @($payload.verification_events)) {
            if ($null -ne $event) { [void]$CollectionState.verification_events.Add($event) }
        }
        $providerOptional = $Optional -or ([bool]$payload.optional)
        [void](Add-McProviderDiagnostic -Diagnostics $CollectionState.diagnostics -Provider $Provider -Health ([string]$payload.health) -DurationMs $duration -ResultCount ([int]$payload.result_count) -WarningCount $warnings.Count -CoverageComplete ([bool]$payload.coverage_complete) -Optional $providerOptional)
        return $payload
    }
    catch {
        $duration = (([System.Diagnostics.Stopwatch]::GetTimestamp() - $started) * 1000.0) / [System.Diagnostics.Stopwatch]::Frequency
        Add-McDiagnosticError -Diagnostics $CollectionState.diagnostics -Message ("{0}: {1}" -f $Provider, $_.Exception.Message)
        [void]$CollectionState.provider_failures.Add([pscustomobject][ordered]@{
                provider = $Provider
                health = 'failed'
                message = (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message)
            })
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
        local_diagnostics = [ordered]@{
            version_normalization = [System.Collections.Generic.List[object]]::new()
        }
        verification_events = [System.Collections.Generic.List[object]]::new()
        provider_failures = [System.Collections.Generic.List[object]]::new()
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
            $normalizedEntity = ConvertTo-McNormalizedEntityVersion -Entity $entity
            $rawVersion = Get-McCollectionProperty -InputObject (Get-McCollectionProperty -InputObject $entity -Name 'observed') -Name 'version'
            $normalizedVersion = Get-McCollectionProperty -InputObject (Get-McCollectionProperty -InputObject $normalizedEntity -Name 'observed') -Name 'version'
            if (-not [string]::IsNullOrWhiteSpace([string]$rawVersion) -and [string]$rawVersion -cne [string]$normalizedVersion) {
                [void]$CollectionState.local_diagnostics.version_normalization.Add([pscustomobject][ordered]@{
                        module = $Module
                        id = [string]$entity.id
                        input_hash = Get-McSha256Hex -Text ([string]$rawVersion)
                        canonical_version = [string]$normalizedVersion
                    })
            }
            $list = $CollectionState.observations.software[$Module]
            $existingIndex = -1
            for ($index = 0; $index -lt $list.Count; $index++) {
                if ([string]$list[$index].id -ieq [string]$normalizedEntity.id) {
                    $existingIndex = $index
                    break
                }
            }
            if ($existingIndex -ge 0) {
                $list[$existingIndex] = $normalizedEntity
            }
            else {
                [void]$list.Add($normalizedEntity)
            }
        }
    }
}

function Get-McCollectionProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-McCollectionProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Value
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        $InputObject[$Name] = $Value
        return
    }
    if ($null -ne $InputObject.PSObject.Properties[$Name]) {
        $InputObject.$Name = $Value
    }
    else {
        Add-Member -InputObject $InputObject -MemberType NoteProperty -Name $Name -Value $Value
    }
}

function Remove-McCollectionProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { [void]$InputObject.Remove($Name) }
        return
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { $InputObject.PSObject.Properties.Remove($Name) }
}

function ConvertTo-McNormalizedEntityVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Entity
    )

    $copy = Copy-McJsonObject -InputObject $Entity
    $observed = Get-McCollectionProperty -InputObject $copy -Name 'observed'
    $rawVersion = Get-McCollectionProperty -InputObject $observed -Name 'version'
    if ([string]::IsNullOrWhiteSpace([string]$rawVersion)) {
        return $copy
    }

    $semantic = ConvertTo-McSemanticVersion -Text ([string]$rawVersion) -EntityId ([string]$copy.id)
    if ([string]::IsNullOrWhiteSpace($semantic)) {
        Remove-McCollectionProperty -InputObject $observed -Name 'version'
    }
    else {
        Set-McCollectionProperty -InputObject $observed -Name 'version' -Value $semantic
    }
    return $copy
}

function Add-McCollectionMachineShells {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Machine,

        [AllowNull()]
        [object[]]$Shells
    )

    $map = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($shell in @(Get-McCollectionProperty -InputObject $Machine -Name 'shells')) {
        if ($null -ne $shell -and -not [string]::IsNullOrWhiteSpace([string]$shell.id)) {
            $map[[string]$shell.id] = $shell
        }
    }
    foreach ($shell in @($Shells)) {
        if ($null -ne $shell -and -not [string]::IsNullOrWhiteSpace([string]$shell.id)) {
            $map[[string]$shell.id] = ConvertTo-McNormalizedEntityVersion -Entity $shell
        }
    }
    Set-McCollectionProperty -InputObject $Machine -Name 'shells' -Value @($map.Values | Sort-Object id)
}

function Merge-McCollectionGpuVerifications {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Machine,

        [AllowNull()]
        [object[]]$Verifications
    )

    if ($null -eq (Get-McCollectionProperty -InputObject $Machine -Name 'hardware')) {
        Set-McCollectionProperty -InputObject $Machine -Name 'hardware' -Value ([pscustomobject][ordered]@{})
    }
    $hardware = Get-McCollectionProperty -InputObject $Machine -Name 'hardware'
    $gpus = [System.Collections.Generic.List[object]]::new()
    foreach ($gpu in @(Get-McCollectionProperty -InputObject $hardware -Name 'gpus')) {
        if ($null -ne $gpu) { [void]$gpus.Add($gpu) }
    }

    foreach ($verification in @($Verifications)) {
        if ($null -eq $verification -or [string]::IsNullOrWhiteSpace([string]$verification.name)) { continue }
        $match = @($gpus | Where-Object { [string]$_.name -eq [string]$verification.name } | Select-Object -First 1)
        if ($match.Count -eq 0) {
            $record = [ordered]@{
                name = [string]$verification.name
                verification = [string]$verification.verification
                vram_source = [string]$verification.vram_source
            }
            if ($null -ne $verification.PSObject.Properties['driver_version']) { $record.driver_version = [string]$verification.driver_version }
            if ($null -ne $verification.PSObject.Properties['vram_bytes']) { $record.vram_bytes = [int64]$verification.vram_bytes; $record.vram_status = 'verified' }
            [void]$gpus.Add([pscustomobject]$record)
            continue
        }
        $record = $match[0]
        foreach ($name in @('driver_version', 'vram_bytes', 'vram_source', 'verification')) {
            $property = $verification.PSObject.Properties[$name]
            if ($null -ne $property -and $null -ne $property.Value) {
                Set-McCollectionProperty -InputObject $record -Name $name -Value (Copy-McValue -InputObject $property.Value)
            }
        }
        if ($null -ne $verification.PSObject.Properties['vram_bytes']) {
            Set-McCollectionProperty -InputObject $record -Name 'vram_status' -Value 'verified'
        }
        $existingEvidence = @((Get-McCollectionProperty -InputObject $record -Name 'evidence') | Where-Object { $null -ne $_ })
        $newEvidence = @((Get-McCollectionProperty -InputObject $verification -Name 'evidence') | Where-Object { $null -ne $_ })
        Set-McCollectionProperty -InputObject $record -Name 'evidence' -Value @($existingEvidence + $newEvidence)
    }
    Set-McCollectionProperty -InputObject $hardware -Name 'gpus' -Value @($gpus | Sort-Object name)
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
            if ($property.Name -ne 'candidates') { $machine[$property.Name] = $property.Value }
        }
        foreach ($candidate in @($shells.value.candidates)) {
            if ($null -ne $candidate) { Add-McCandidateListItem -CollectionState $state -Candidate $candidate }
        }
    }
    if ($null -ne $shells.local) {
        $state.local_diagnostics.shells = $shells.local
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

    $gitForWindows = Invoke-McSafeProvider -CollectionState $state -Provider 'git-for-windows' -Action {
        Get-McGitForWindowsObservation
    }
    if ($null -ne $gitForWindows.value) {
        Add-McModuleObservations -CollectionState $state -Module 'development' -Entities @($gitForWindows.value.development_entities)
        Add-McCollectionMachineShells -Machine $machine -Shells @($gitForWindows.value.shells)
        foreach ($candidate in @($gitForWindows.value.candidates)) {
            if ($null -ne $candidate) { Add-McCandidateListItem -CollectionState $state -Candidate $candidate }
        }
    }

    $visualStudio = Invoke-McSafeProvider -CollectionState $state -Provider 'visual-studio-msvc-sdk' -Action {
        Get-McVisualStudioObservation
    } -Optional $true
    if ($null -ne $visualStudio.value) {
        Add-McModuleObservations -CollectionState $state -Module 'development' -Entities @($visualStudio.value.development_entities)
        foreach ($candidate in @($visualStudio.value.candidates)) {
            if ($null -ne $candidate) { Add-McCandidateListItem -CollectionState $state -Candidate $candidate }
        }
    }

    $hardwareVerifiers = Invoke-McSafeProvider -CollectionState $state -Provider 'nvidia-smi' -Action {
        Get-McNvidiaSmiObservation
    } -Optional $true
    if ($null -ne $hardwareVerifiers.value) {
        Merge-McCollectionGpuVerifications -Machine $machine -Verifications @($hardwareVerifiers.value.gpu_verifications)
    }

    $hostTools = Invoke-McSafeProvider -CollectionState $state -Provider 'host-authoritative-tools' -Action {
        Get-McHostAuthoritativeToolObservation
    }
    if ($null -ne $hostTools.value) {
        Add-McModuleObservations -CollectionState $state -Module 'development' -Entities @($hostTools.value.development_entities)
        Add-McModuleObservations -CollectionState $state -Module 'ai' -Entities @($hostTools.value.ai_entities)
        foreach ($candidate in @($hostTools.value.candidates)) {
            if ($null -ne $candidate) { Add-McCandidateListItem -CollectionState $state -Candidate $candidate }
        }
    }
    if ($null -ne $hostTools.local) { $state.local_diagnostics.host_authoritative_tools = $hostTools.local }

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

        $bounded = Invoke-McSafeProvider -CollectionState $state -Provider 'bounded-filesystem-discovery' -Action {
            Get-McBoundedDiscoveryCandidates -RepoRoot $RunContext.repo_root
        } -Optional $true
        foreach ($candidate in @($bounded.value)) {
            if ($null -ne $candidate) {
                Add-McCandidateListItem -CollectionState $state -Candidate $candidate
            }
        }
        if ($null -ne $bounded.local) {
            $state.local_diagnostics.bounded_filesystem_discovery = $bounded.local
        }

        $everything = Invoke-McSafeProvider -CollectionState $state -Provider 'everything-index' -Action {
            Get-McEverythingCandidates -RepoRoot $RunContext.repo_root
        } -Optional $true
        foreach ($candidate in @($everything.value)) {
            if ($null -ne $candidate) {
                Add-McCandidateListItem -CollectionState $state -Candidate $candidate
            }
        }
        if ($null -ne $everything.local) {
            $state.local_diagnostics.everything_index = $everything.local
        }
    }

    $state.observations.machine = [pscustomobject]$machine
    $derivedRelationships = @(Get-McStrongRelationships -Observations ([pscustomobject]$state.observations))
    foreach ($relationship in $derivedRelationships) {
        if ($null -ne $relationship) {
            [void]$state.observations.relationships.Add($relationship)
        }
    }
    $state.local_diagnostics.relationships = [pscustomobject][ordered]@{
        derived_count = $derivedRelationships.Count
        total_count = $state.observations.relationships.Count
    }

    $state.observations.verification_events = @($state.verification_events)
    $state.observations.provider_failures = @($state.provider_failures)
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
        }) -Diagnostics $state.diagnostics -LocalDiagnostics $state.local_diagnostics
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
        'git-for-windows.ps1',
        'hardware-verifiers.ps1',
        'visual-studio.ps1',
        'host-tool-verifiers.ps1',
        'runtimes.ps1',
        'ai-tools.ps1',
        'network.ps1',
        'registry-apps.ps1',
        'projects.ps1',
        'discovery-bounded.ps1',
        'discovery-everything.ps1'
    )) {
    $collectorPath = Join-Path $collectorRoot $collector
    if (Test-Path -LiteralPath $collectorPath -PathType Leaf) {
        . $collectorPath
    }
}
