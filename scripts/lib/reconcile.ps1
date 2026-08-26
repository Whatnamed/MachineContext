Set-StrictMode -Version Latest

function Get-McObjectPropertyOrNull {
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

function Set-McObjectProperty {
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

function Remove-McObjectProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) { return }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { [void]$InputObject.Remove($Name) }
        return
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) { $InputObject.PSObject.Properties.Remove($Name) }
}

function Set-McObservedVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Record,

        [Parameter(Mandatory)]
        [object]$Event
    )

    $state = [string]$Event.verification
    if ($state -notin @('verified-present', 'unverified', 'stale', 'verified-absent')) { return }
    $observed = Get-McObjectPropertyOrNull -InputObject $Record -Name 'observed'
    if ($null -eq $observed) {
        $observed = [pscustomobject][ordered]@{}
        Set-McObjectProperty -InputObject $Record -Name 'observed' -Value $observed
    }

    if ($state -eq 'verified-absent') {
        $lastKnown = Copy-McJsonObject -InputObject $observed
        Remove-McObjectProperty -InputObject $lastKnown -Name 'last_known'
        Set-McObjectProperty -InputObject $observed -Name 'last_known' -Value $lastKnown
        Set-McObjectProperty -InputObject $observed -Name 'present' -Value $false
    }
    elseif ($state -eq 'verified-present') {
        Set-McObjectProperty -InputObject $observed -Name 'present' -Value $true
    }

    Set-McObjectProperty -InputObject $observed -Name 'verification' -Value $state
    if ($null -ne $Event.PSObject.Properties['provider']) {
        Set-McObjectProperty -InputObject $observed -Name 'verification_provider' -Value ([string]$Event.provider)
    }
    if ($null -ne $Event.PSObject.Properties['reason']) {
        Set-McObjectProperty -InputObject $observed -Name 'verification_reason' -Value ([string]$Event.reason)
    }
}

function Get-McProviderFailureEvents {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Failures
    )

    $targets = [ordered]@{
        'runtimes-package-managers-toolchain' = @([pscustomobject]@{ module = 'development'; ids = @('node', 'python', 'python-launcher', 'go', 'rustc', 'cargo', 'rustup', 'java', 'flutter', 'dart', 'ruby', 'php', 'deno', 'npm', 'pnpm', 'yarn', 'bun', 'pip', 'pipx', 'uv', 'uvx', 'conda', 'mamba', 'nvm', 'fnm', 'volta', 'pyenv', 'mise', 'git-lfs', 'cmake', 'ninja', 'adb', 'nvcc', 'gh', 'docker', 'kubectl', 'vercel', 'wrangler', 'firebase', 'aws', 'az', 'gcloud', 'terraform', 'winget', 'choco', 'scoop') })
        'ai-tooling' = @([pscustomobject]@{ module = 'ai'; ids = @('dsh', 'agy', 'claude-code', 'gemini-cli', 'cursor-cli', 'windsurf-cli') })
        'shells-path-resolution' = @([pscustomobject]@{ module = 'machine.shells'; ids = @('shell-pwsh', 'shell-windows-powershell', 'shell-cmd', 'shell-ssh') })
        'git-for-windows' = @([pscustomobject]@{ module = 'development'; ids = @('git') }, [pscustomobject]@{ module = 'machine.shells'; ids = @('shell-git-bash') })
        'visual-studio-msvc-sdk' = @([pscustomobject]@{ module = 'development'; ids = @('visual-studio') })
        'host-authoritative-tools' = @([pscustomobject]@{ module = 'development'; ids = @('dotnet', 'code', 'supabase') }, [pscustomobject]@{ module = 'ai'; ids = @('codex-cli', 'codex-desktop') })
        'network-local-services' = @([pscustomobject]@{ module = 'network.wsl'; ids = @('wsl') })
    }
    $events = [System.Collections.Generic.List[object]]::new()
    foreach ($failure in @($Failures)) {
        if ($null -eq $failure) { continue }
        $provider = [string]$failure.provider
        foreach ($target in @($targets[$provider])) {
            foreach ($id in @($target.ids)) {
                [void]$events.Add([pscustomobject][ordered]@{
                        module = [string]$target.module
                        id = [string]$id
                        provider = $provider
                        verification = 'unverified'
                        reason = 'provider-failed'
                    })
            }
        }
    }
    return @($events)
}

function Merge-McObservedObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Previous,

        [AllowNull()]
        [object]$Current
    )

    $merged = if ($null -ne $Previous) { Copy-McJsonObject -InputObject $Previous } else { [pscustomobject][ordered]@{} }
    if ($null -eq $Current) { return $merged }

    foreach ($property in (Get-McPropertyEntries -InputObject $Current)) {
        $value = $property.Value
        if ($null -eq $value) { continue }
        if ($property.Name -eq 'evidence') {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in @((Get-McObjectPropertyOrNull -InputObject $merged -Name 'evidence') | Where-Object { $null -ne $_ })) { [void]$items.Add($item) }
            foreach ($item in @($value | Where-Object { $null -ne $_ })) { [void]$items.Add($item) }
            $unique = [System.Collections.Generic.List[object]]::new()
            $seen = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($item in $items) {
                $key = ConvertTo-McJsonText -InputObject $item
                if ($seen.Add($key)) { [void]$unique.Add($item) }
            }
            Set-McObjectProperty -InputObject $merged -Name $property.Name -Value @($unique)
        }
        else {
            Set-McObjectProperty -InputObject $merged -Name $property.Name -Value (Copy-McJsonObject -InputObject $value)
        }
    }

    return $merged
}

function New-McObservedEntityRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Observation,

        [AllowNull()]
        [object]$Existing
    )

    if ($null -ne $Existing) {
        $record = Copy-McJsonObject -InputObject $Existing
        $previousObserved = Get-McObjectPropertyOrNull -InputObject $record -Name 'observed'
        $currentObserved = Get-McObjectPropertyOrNull -InputObject $Observation -Name 'observed'
        $currentVerification = Get-McObjectPropertyOrNull -InputObject $currentObserved -Name 'verification'
        $currentPresent = Get-McObjectPropertyOrNull -InputObject $currentObserved -Name 'present'
        $previousPresent = Get-McObjectPropertyOrNull -InputObject $previousObserved -Name 'present'
        if ($currentVerification -in @('unverified', 'stale') -and $currentPresent -eq $false -and $previousPresent -eq $true) {
            $safeCurrent = Copy-McJsonObject -InputObject $currentObserved
            Remove-McObjectProperty -InputObject $safeCurrent -Name 'present'
            $currentObserved = $safeCurrent
        }
        Set-McObjectProperty -InputObject $record -Name 'observed' -Value (Merge-McObservedObject -Previous $previousObserved -Current $currentObserved)
        $name = Get-McObjectPropertyOrNull -InputObject $Observation -Name 'name'
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) { Set-McObjectProperty -InputObject $record -Name 'name' -Value ([string]$name) }
        return $record
    }

    $observed = Copy-McJsonObject -InputObject $Observation.observed
    $observedPresent = Get-McObjectPropertyOrNull -InputObject $observed -Name 'present'
    $observedVerification = Get-McObjectPropertyOrNull -InputObject $observed -Name 'verification'
    if ($null -ne $observed -and $observedPresent -eq $true -and $null -eq $observedVerification) {
        Set-McObjectProperty -InputObject $observed -Name 'verification' -Value 'verified-present'
    }
    $record = [ordered]@{
        schema_version = 1
        id = [string]$Observation.id
        kind = [string]$Observation.kind
        name = [string]$Observation.name
        observed = $observed
        curated = [ordered]@{ status = 'unknown' }
    }
    return [pscustomobject]$record
}

function Merge-McSoftwareModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Module,

        [AllowNull()]
        [object[]]$Observations,

        [AllowNull()]
        [object[]]$VerificationEvents = @(),

        [ValidateSet('development', 'ai')]
        [string]$ModuleName = 'development'
    )

    $map = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($existing in @($Module.software)) {
        if ($null -ne $existing -and -not [string]::IsNullOrWhiteSpace([string]$existing.id)) {
            $map[[string]$existing.id] = ConvertTo-McNormalizedEntityVersion -Entity $existing
        }
    }

    foreach ($observation in @($Observations | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.id) })) {
        $normalizedObservation = ConvertTo-McNormalizedEntityVersion -Entity $observation
        $existing = if ($map.ContainsKey([string]$normalizedObservation.id)) { $map[[string]$normalizedObservation.id] } else { $null }
        $map[[string]$normalizedObservation.id] = New-McObservedEntityRecord -Observation $normalizedObservation -Existing $existing
    }

    foreach ($event in @($VerificationEvents | Where-Object { $null -ne $_ -and [string]$_.module -eq $ModuleName -and -not [string]::IsNullOrWhiteSpace([string]$_.id) })) {
        if ($map.ContainsKey([string]$event.id)) {
            Set-McObservedVerification -Record $map[[string]$event.id] -Event $event
        }
    }

    if ($ModuleName -eq 'ai' -and $map.ContainsKey('codex') -and $map.ContainsKey('codex-cli')) {
        $legacyCodex = $map['codex']
        $codexCli = $map['codex-cli']
        $legacyObserved = Get-McObjectPropertyOrNull -InputObject $legacyCodex -Name 'observed'
        $currentObserved = Get-McObjectPropertyOrNull -InputObject $codexCli -Name 'observed'
        Set-McObjectProperty -InputObject $codexCli -Name 'observed' -Value (Merge-McObservedObject -Previous $legacyObserved -Current $currentObserved)
        $legacyCurated = Get-McObjectPropertyOrNull -InputObject $legacyCodex -Name 'curated'
        $currentCurated = Get-McObjectPropertyOrNull -InputObject $codexCli -Name 'curated'
        if ($null -ne $legacyCurated -and ($null -eq $currentCurated -or [string]$currentCurated.status -eq 'unknown')) {
            Set-McObjectProperty -InputObject $codexCli -Name 'curated' -Value (Copy-McJsonObject -InputObject $legacyCurated)
        }
        [void]$map.Remove('codex')
    }

    $Module.software = @($map.Values | Sort-Object id)
    $meta = Get-McObjectPropertyOrNull -InputObject $Module -Name 'meta'
    if ($null -eq $meta) {
        Set-McObjectProperty -InputObject $Module -Name 'meta' -Value ([pscustomobject][ordered]@{ state = 'observed' })
    }
    else {
        Set-McObjectProperty -InputObject $meta -Name 'state' -Value 'observed'
    }
    return $Module
}

function Set-McCanonicalObservedSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Document,

        [Parameter(Mandatory)]
        [string]$SectionName,

        [AllowNull()]
        [object]$ObservedValue
    )

    if ($null -eq $ObservedValue) { return }
    $section = Get-McObjectPropertyOrNull -InputObject $Document -Name $SectionName
    if ($null -eq $section) {
        $section = [pscustomobject][ordered]@{
            observed = [pscustomobject][ordered]@{}
            curated = [pscustomobject][ordered]@{}
        }
        Set-McObjectProperty -InputObject $Document -Name $SectionName -Value $section
    }
    $curated = Get-McObjectPropertyOrNull -InputObject $section -Name 'curated'
    if ($null -eq $curated) {
        Set-McObjectProperty -InputObject $section -Name 'curated' -Value ([pscustomobject][ordered]@{})
    }
    Set-McObjectProperty -InputObject $section -Name 'observed' -Value (Copy-McJsonObject -InputObject $ObservedValue)
}

function Merge-McMachineShells {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Machine,

        [AllowNull()]
        [object[]]$Current,

        [AllowNull()]
        [object[]]$VerificationEvents = @()
    )

    $map = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($shell in @((Get-McObjectPropertyOrNull -InputObject $Machine -Name 'shells'))) {
        if ($null -ne $shell -and -not [string]::IsNullOrWhiteSpace([string]$shell.id)) {
            $map[[string]$shell.id] = ConvertTo-McNormalizedEntityVersion -Entity $shell
        }
    }
    foreach ($shell in @($Current | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.id) })) {
        $normalizedShell = ConvertTo-McNormalizedEntityVersion -Entity $shell
        $existing = if ($map.ContainsKey([string]$normalizedShell.id)) { $map[[string]$normalizedShell.id] } else { $null }
        $map[[string]$normalizedShell.id] = New-McObservedEntityRecord -Observation $normalizedShell -Existing $existing
    }
    foreach ($event in @($VerificationEvents | Where-Object { $null -ne $_ -and [string]$_.module -eq 'machine.shells' -and -not [string]::IsNullOrWhiteSpace([string]$_.id) })) {
        if ($map.ContainsKey([string]$event.id)) {
            Set-McObservedVerification -Record $map[[string]$event.id] -Event $event
        }
    }
    Set-McObjectProperty -InputObject $Machine -Name 'shells' -Value @($map.Values | Sort-Object id)
}

function Get-McProjectRecordFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    if ($Id -match '^[a-z0-9._-]+$') {
        return "$Id.json"
    }
    return ('project-{0}.json' -f (Get-McSha256Hex -Text $Id).Substring(0, 20))
}

function Merge-McProjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ContextRoot,

        [Parameter(Mandatory)]
        [object]$ProjectIndex,

        [AllowNull()]
        [object[]]$Candidates
    )

    $projectRoot = Join-Path $ContextRoot 'projects'
    [void](New-Item -ItemType Directory -Path $projectRoot -Force)
    $records = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($file in @(Get-ChildItem -LiteralPath $projectRoot -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('_template.json', 'index.json') })) {
        try {
            $record = Read-McJson -Path $file.FullName
            if (-not [string]::IsNullOrWhiteSpace([string]$record.id)) {
                $records[[string]$record.id] = $record
            }
        }
        catch {
        }
    }

    foreach ($candidate in @($Candidates | Where-Object { $null -ne $_ -and $_.verified -eq $true -and $_.promotion_eligible -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$_.id) })) {
        $id = [string]$candidate.id
        $existing = if ($records.ContainsKey($id)) { $records[$id] } else { $null }
        $record = if ($null -ne $existing) { Copy-McJsonObject -InputObject $existing } else {
            [pscustomobject][ordered]@{
                schema_version = 1
                id = $id
                name = [string]$candidate.name_hint
                observed = Copy-McJsonObject -InputObject $candidate.observed
                curated = [pscustomobject][ordered]@{ status = 'unknown' }
            }
        }
        if ($null -ne $existing) {
            Set-McObjectProperty -InputObject $record -Name 'observed' -Value (Merge-McObservedObject -Previous $record.observed -Current $candidate.observed)
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate.name_hint)) { Set-McObjectProperty -InputObject $record -Name 'name' -Value ([string]$candidate.name_hint) }
        }
        $records[$id] = $record
    }

    $indexRefs = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($records.Values | Sort-Object id)) {
        [void]$indexRefs.Add([pscustomobject][ordered]@{
            id = [string]$record.id
            name = [string]$record.name
            path = [string]$record.observed.local_path
            context_file = ('context/projects/{0}' -f (Get-McProjectRecordFileName -Id ([string]$record.id)))
        })
        Write-McJson -Path (Join-Path $projectRoot (Get-McProjectRecordFileName -Id ([string]$record.id))) -InputObject $record
    }
    $ProjectIndex.projects = @($indexRefs)
    return $ProjectIndex
}

function Merge-McRelationships {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Previous,

        [AllowNull()]
        [object[]]$Current
    )

    $map = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($relationship in @($Previous) + @($Current)) {
        if ($null -eq $relationship) { continue }
        $key = '{0}|{1}|{2}' -f $relationship.from, $relationship.relation, $relationship.to
        $map[$key] = Copy-McJsonObject -InputObject $relationship
    }
    return @($map.Values | Sort-Object from,relation,to)
}

function Update-McPublishedStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Status,

        [Parameter(Mandatory)]
        [object]$Diagnostics,

        [Parameter(Mandatory)]
        [string]$Mode
    )

    $summary = ConvertTo-McPublishedProviderSummary -Providers $Diagnostics.providers
    $previous = Get-McObjectPropertyOrNull -InputObject $Status -Name 'published_verification'
    $previousSummary = if ($null -ne $previous) { @($previous.provider_summary | ForEach-Object { "{0}:{1}" -f $_.provider, $_.health } | Sort-Object) } else { @() }
    $newSummary = @($summary | ForEach-Object { "{0}:{1}" -f $_.provider, $_.health } | Sort-Object)
    $changed = ([string]$Mode -ne [string](Get-McObjectPropertyOrNull -InputObject $previous -Name 'mode')) -or ((ConvertTo-McJsonText -InputObject $previousSummary) -ne (ConvertTo-McJsonText -InputObject $newSummary))
    $previousVerifiedAt = Get-McObjectPropertyOrNull -InputObject $previous -Name 'verified_at'
    if ($changed -or [string]::IsNullOrWhiteSpace([string]$previousVerifiedAt)) {
        $verifiedAt = (Get-Date).ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }
    elseif ($previousVerifiedAt -is [datetime]) {
        $verifiedAt = $previousVerifiedAt.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }
    else {
        $parsedVerifiedAt = [datetime]::MinValue
        $parseStyles = [Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
        $parsed = [datetime]::TryParse(
            [string]$previousVerifiedAt,
            [Globalization.CultureInfo]::InvariantCulture,
            $parseStyles,
            [ref]$parsedVerifiedAt
        )
        $verifiedAt = if ($parsed) {
            $parsedVerifiedAt.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
        }
        else {
            [string]$previousVerifiedAt
        }
    }
    $Status.state = if ($Diagnostics.overall_health -eq 'success') { 'verified' } else { 'partial' }
    $Status.published_verification = [pscustomobject][ordered]@{
        mode = $Mode
        verified_at = $verifiedAt
        provider_summary = $summary
    }
    return $Status
}

function Invoke-McReconciliation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RunContext,

        [Parameter(Mandatory)]
        [object]$CollectionResult
    )

    Copy-McCanonicalToStage -RunContext $RunContext
    $contextRoot = $RunContext.proposed_context
    $observations = $CollectionResult.observations
    $verificationEvents = @((Get-McObjectPropertyOrNull -InputObject $observations -Name 'verification_events'))
    $verificationEvents += @(Get-McProviderFailureEvents -Failures @((Get-McObjectPropertyOrNull -InputObject $observations -Name 'provider_failures')))

    $machinePath = Join-Path $contextRoot 'machine.json'
    $machine = Read-McJson -Path $machinePath
    Set-McCanonicalObservedSection -Document $machine -SectionName 'system' -ObservedValue $observations.machine.system
    Set-McCanonicalObservedSection -Document $machine -SectionName 'hardware' -ObservedValue $observations.machine.hardware
    if ($null -ne $observations.machine.storage) { Set-McObjectProperty -InputObject $machine -Name 'storage' -Value @($observations.machine.storage) }
    Merge-McMachineShells -Machine $machine -Current @($observations.machine.shells) -VerificationEvents $verificationEvents
    if ($null -ne $observations.machine.paths) {
        $existingKnownRoots = @((Get-McObjectPropertyOrNull -InputObject $machine.paths -Name 'known_roots'))
        Set-McObjectProperty -InputObject $machine -Name 'paths' -Value (Copy-McJsonObject -InputObject $observations.machine.paths)
        if ($null -eq (Get-McObjectPropertyOrNull -InputObject $machine.paths -Name 'known_roots')) { $machine.paths | Add-Member -MemberType NoteProperty -Name known_roots -Value $existingKnownRoots }
    }
    if ($null -ne $observations.machine.environment) { Set-McObjectProperty -InputObject $machine -Name 'environment' -Value (Copy-McJsonObject -InputObject $observations.machine.environment) }
    if ($null -ne $observations.machine.command_resolution) { Set-McObjectProperty -InputObject $machine -Name 'command_resolution' -Value @($observations.machine.command_resolution) }
    if ($null -ne $observations.machine.constraints) { Set-McObjectProperty -InputObject $machine -Name 'constraints' -Value @($observations.machine.constraints) }
    Write-McJson -Path $machinePath -InputObject $machine

    $networkPath = Join-Path $contextRoot 'network.json'
    $network = Read-McJson -Path $networkPath
    Set-McCanonicalObservedSection -Document $network -SectionName 'primary_network' -ObservedValue $observations.network.primary_network.observed
    Set-McCanonicalObservedSection -Document $network -SectionName 'proxy' -ObservedValue $observations.network.proxy.observed
    if ($null -ne $observations.network.local_services) { Set-McObjectProperty -InputObject $network -Name 'local_services' -Value @($observations.network.local_services) }
    if ($null -ne $observations.network.ports) { Set-McObjectProperty -InputObject $network -Name 'ports' -Value @($observations.network.ports) }
    if ($null -ne $observations.network.constraints) { Set-McObjectProperty -InputObject $network -Name 'constraints' -Value @($observations.network.constraints) }
    if ($null -ne $observations.network.wsl) {
        $currentWsl = $observations.network.wsl
        $existingWsl = Get-McObjectPropertyOrNull -InputObject $network -Name 'wsl'
        $currentWslVerification = Get-McObjectPropertyOrNull -InputObject $currentWsl -Name 'verification'
        if ($null -ne $existingWsl -and $currentWslVerification -in @('unverified', 'stale')) {
            Set-McObjectProperty -InputObject $network -Name 'wsl' -Value (Merge-McObservedObject -Previous $existingWsl -Current $currentWsl)
        }
        else {
            Set-McObjectProperty -InputObject $network -Name 'wsl' -Value (Copy-McJsonObject -InputObject $currentWsl)
        }
    }
    $wslRecord = Get-McObjectPropertyOrNull -InputObject $network -Name 'wsl'
    foreach ($event in @($verificationEvents | Where-Object { $null -ne $_ -and [string]$_.module -eq 'network.wsl' -and [string]$_.id -eq 'wsl' })) {
        if ($null -ne $wslRecord) {
            $wrapper = [pscustomobject][ordered]@{ id = 'wsl'; observed = $wslRecord }
            Set-McObservedVerification -Record $wrapper -Event $event
            Set-McObjectProperty -InputObject $network -Name 'wsl' -Value $wrapper.observed
        }
    }
    Write-McJson -Path $networkPath -InputObject $network

    foreach ($moduleName in @('development', 'ai')) {
        $path = Join-Path $contextRoot ("software\{0}.json" -f $moduleName)
        $module = Read-McJson -Path $path
        $module = Merge-McSoftwareModule -Module $module -ModuleName $moduleName -Observations @($observations.software.$moduleName) -VerificationEvents $verificationEvents
        Write-McJson -Path $path -InputObject $module
    }

    $projectIndexPath = Join-Path $contextRoot 'projects\index.json'
    $projectIndex = Read-McJson -Path $projectIndexPath
    $projectIndex = Merge-McProjects -ContextRoot $contextRoot -ProjectIndex $projectIndex -Candidates @($observations.projects)
    Write-McJson -Path $projectIndexPath -InputObject $projectIndex

    $relationshipsPath = Join-Path $contextRoot 'relationships.json'
    $relationships = Read-McJson -Path $relationshipsPath
    $mergedRelationships = [System.Collections.Generic.List[object]]::new()
    foreach ($relationship in @(Merge-McRelationships -Previous @($relationships.relationships) -Current @($observations.relationships))) {
        if ($null -ne $relationship) { [void]$mergedRelationships.Add($relationship) }
    }
    Set-McObjectProperty -InputObject $relationships -Name 'relationships' -Value $mergedRelationships
    Write-McJson -Path $relationshipsPath -InputObject $relationships

    $statusPath = Join-Path $contextRoot 'status.json'
    $status = Read-McJson -Path $statusPath
    $status = Update-McPublishedStatus -Status $status -Diagnostics $CollectionResult.diagnostics -Mode $RunContext.mode
    Write-McJson -Path $statusPath -InputObject $status

    return [pscustomobject][ordered]@{
        run_context = $RunContext
        proposed_context = $contextRoot
        proposed_current = $RunContext.proposed_current
        diagnostics = $CollectionResult.diagnostics
    }
}
