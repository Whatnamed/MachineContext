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
            foreach ($item in @((Get-McObjectPropertyOrNull -InputObject $merged -Name 'evidence'))) { [void]$items.Add($item) }
            foreach ($item in @($value)) { [void]$items.Add($item) }
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
        Set-McObjectProperty -InputObject $record -Name 'observed' -Value (Merge-McObservedObject -Previous $previousObserved -Current $currentObserved)
        $name = Get-McObjectPropertyOrNull -InputObject $Observation -Name 'name'
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) { Set-McObjectProperty -InputObject $record -Name 'name' -Value ([string]$name) }
        return $record
    }

    $record = [ordered]@{
        schema_version = 1
        id = [string]$Observation.id
        kind = [string]$Observation.kind
        name = [string]$Observation.name
        observed = Copy-McJsonObject -InputObject $Observation.observed
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
        [object[]]$Observations
    )

    $map = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($existing in @($Module.software)) {
        if ($null -ne $existing -and -not [string]::IsNullOrWhiteSpace([string]$existing.id)) {
            $map[[string]$existing.id] = Copy-McJsonObject -InputObject $existing
        }
    }

    foreach ($observation in @($Observations | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.id) })) {
        $existing = if ($map.ContainsKey([string]$observation.id)) { $map[[string]$observation.id] } else { $null }
        $map[[string]$observation.id] = New-McObservedEntityRecord -Observation $observation -Existing $existing
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
        Write-McJson -Path (Join-Path $projectRoot (Get-McProjectRecordFileName -Id $id)) -InputObject $record
    }

    $indexRefs = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($records.Values | Sort-Object id)) {
        [void]$indexRefs.Add([pscustomobject][ordered]@{
            id = [string]$record.id
            name = [string]$record.name
            path = [string]$record.observed.local_path
            context_file = ('context/projects/{0}' -f (Get-McProjectRecordFileName -Id ([string]$record.id)))
        })
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

    $machinePath = Join-Path $contextRoot 'machine.json'
    $machine = Read-McJson -Path $machinePath
    Set-McCanonicalObservedSection -Document $machine -SectionName 'system' -ObservedValue $observations.machine.system
    Set-McCanonicalObservedSection -Document $machine -SectionName 'hardware' -ObservedValue $observations.machine.hardware
    if ($null -ne $observations.machine.storage) { Set-McObjectProperty -InputObject $machine -Name 'storage' -Value @($observations.machine.storage) }
    if ($null -ne $observations.machine.shells) { Set-McObjectProperty -InputObject $machine -Name 'shells' -Value @($observations.machine.shells) }
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
    if ($null -ne $observations.network.wsl) { Set-McObjectProperty -InputObject $network -Name 'wsl' -Value (Copy-McJsonObject -InputObject $observations.network.wsl) }
    Write-McJson -Path $networkPath -InputObject $network

    foreach ($moduleName in @('development', 'ai')) {
        $path = Join-Path $contextRoot ("software\{0}.json" -f $moduleName)
        $module = Read-McJson -Path $path
        $module = Merge-McSoftwareModule -Module $module -Observations @($observations.software.$moduleName)
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
