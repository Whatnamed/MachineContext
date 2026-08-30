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
    if ($null -eq $property) { $InputObject.PSObject.Properties.Remove($Name) }
}

# Existing canonical files feed curated-intent preservation; a parse failure
# here must abort the run (matching the validation failure policy) instead of
# being swallowed, because the fresh observed record would silently overwrite
# curated meaning.
function Read-McCanonicalJsonOrThrow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        return Read-McJson -Path $Path
    }
    catch {
        throw ("Canonical file '{0}' could not be parsed ({1}); refusing to overwrite it silently because curated intent could be lost." -f $Path, $_.Exception.Message)
    }
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
        # Providers without an entity map contribute no entity-level events;
        # their failure stays visible in the provider diagnostics instead.
        if (-not $targets.Contains($provider)) { continue }
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
            $previousValue = Get-McObjectPropertyOrNull -InputObject $merged -Name $property.Name
            $valueVerification = [string](Get-McObjectPropertyOrNull -InputObject $value -Name 'verification')
            if ((Test-McMapping -InputObject $value) -and $valueVerification -in @('unverified', 'stale') -and (Test-McMapping -InputObject $previousValue)) {
                $safeValue = Copy-McJsonObject -InputObject $value
                $currentPresent = Get-McObjectPropertyOrNull -InputObject $safeValue -Name 'present'
                $previousPresent = Get-McObjectPropertyOrNull -InputObject $previousValue -Name 'present'
                if ($currentPresent -eq $false -and $previousPresent -eq $true) {
                    Remove-McObjectProperty -InputObject $safeValue -Name 'present'
                }
                Set-McObjectProperty -InputObject $merged -Name $property.Name -Value (Merge-McObservedObject -Previous $previousValue -Current $safeValue)
            }
            elseif ((Test-McMapping -InputObject $value) -and $valueVerification -eq 'verified-absent' -and (Test-McMapping -InputObject $previousValue)) {
                $safeValue = Copy-McJsonObject -InputObject $value
                if ($null -eq (Get-McObjectPropertyOrNull -InputObject $safeValue -Name 'last_known')) {
                    $lastKnown = Copy-McJsonObject -InputObject $previousValue
                    Remove-McObjectProperty -InputObject $lastKnown -Name 'last_known'
                    Set-McObjectProperty -InputObject $safeValue -Name 'last_known' -Value $lastKnown
                }
                Set-McObjectProperty -InputObject $merged -Name $property.Name -Value $safeValue
            }
            else {
                Set-McObjectProperty -InputObject $merged -Name $property.Name -Value (Copy-McJsonObject -InputObject $value)
            }
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
        curated = [ordered]@{}
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
            $map[[string]$existing.id] = ConvertTo-McHostSafeSoftwareEntity -Entity (ConvertTo-McNormalizedEntityVersion -Entity $existing)
        }
    }

    foreach ($observation in @($Observations | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.id) })) {
        $normalizedObservation = ConvertTo-McHostSafeSoftwareEntity -Entity (ConvertTo-McNormalizedEntityVersion -Entity $observation)
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
        $currentStatus = [string](Get-McObjectPropertyOrNull -InputObject $currentCurated -Name 'status')
        if ($null -ne $legacyCurated -and ($null -eq $currentCurated -or $currentStatus -in @('', 'unknown') -or (@($currentCurated.PSObject.Properties).Count -eq 0))) {
            Set-McObjectProperty -InputObject $codexCli -Name 'curated' -Value (Copy-McJsonObject -InputObject $legacyCurated)
        }
        [void]$map.Remove('codex')
    }

    $Module.software = @($map.Values | Sort-Object { [string]$_.id })
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
    Set-McObjectProperty -InputObject $Machine -Name 'shells' -Value @($map.Values | Sort-Object { [string]$_.id })
}

function Get-McProjectRecordFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    if ($Id -cmatch '^[a-z0-9._-]+$') {
        return "$Id.json"
    }
    return ('project-{0}.json' -f (Get-McSha256Hex -Text $Id).Substring(0, 20))
}

function Test-McProjectCuratedIntent {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Record
    )

    $curated = Get-McObjectPropertyOrNull -InputObject $Record -Name 'curated'
    if ($null -eq $curated) {
        return $false
    }

    $status = [string](Get-McObjectPropertyOrNull -InputObject $curated -Name 'status')
    if (-not [string]::IsNullOrWhiteSpace($status) -and $status -ine 'unknown') {
        return $true
    }

    foreach ($property in @($curated.PSObject.Properties)) {
        if ([string]$property.Name -ne 'status' -and $null -ne $property.Value) {
            return $true
        }
    }
    return $false
}

function ConvertTo-McHostSafeSoftwareEntity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Entity
    )

    $copy = Copy-McJsonObject -InputObject $Entity
    $observed = Get-McObjectPropertyOrNull -InputObject $copy -Name 'observed'
    if ($null -eq $observed) {
        return $copy
    }

    $executable = [string](Get-McObjectPropertyOrNull -InputObject $observed -Name 'executable')
    $install = Get-McObjectPropertyOrNull -InputObject $observed -Name 'install'
    $installRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($installItem in @($install)) {
        $root = [string](Get-McObjectPropertyOrNull -InputObject $installItem -Name 'root')
        if (-not [string]::IsNullOrWhiteSpace($root)) { [void]$installRoots.Add($root) }
    }
    $resolutions = @((Get-McObjectPropertyOrNull -InputObject $observed -Name 'command_resolution'))
    $processResolution = @($resolutions | Where-Object { Test-McCollectorProcessOnlyPath -Path ([string](Get-McObjectPropertyOrNull -InputObject $_ -Name 'executable')) })
    $primaryProcess = Test-McCollectorProcessOnlyPath -Path $executable
    $rootProcess = @($installRoots | Where-Object { Test-McCollectorProcessOnlyPath -Path $_ }).Count -gt 0
    if (-not $primaryProcess -and -not $rootProcess -and $processResolution.Count -eq 0) {
        return $copy
    }

    $keptResolutions = @($resolutions | Where-Object { -not (Test-McCollectorProcessOnlyPath -Path ([string](Get-McObjectPropertyOrNull -InputObject $_ -Name 'executable'))) })
    Set-McObjectProperty -InputObject $observed -Name 'command_resolution' -Value @($keptResolutions)

    if ($primaryProcess -or $rootProcess) {
        Remove-McObjectProperty -InputObject $observed -Name 'version'
        Remove-McObjectProperty -InputObject $observed -Name 'present'
        Remove-McObjectProperty -InputObject $observed -Name 'evidence'
        if ($keptResolutions.Count -gt 0) {
            Set-McObjectProperty -InputObject $observed -Name 'executable' -Value ([string](Get-McObjectPropertyOrNull -InputObject $keptResolutions[0] -Name 'executable'))
        }
        else {
            Remove-McObjectProperty -InputObject $observed -Name 'executable'
        }
        if ($rootProcess) {
            if ($install -is [System.Collections.IDictionary]) {
                Remove-McObjectProperty -InputObject $install -Name 'root'
                if (@(Get-McPropertyEntries -InputObject $install).Count -eq 0) {
                    Remove-McObjectProperty -InputObject $observed -Name 'install'
                }
            }
            elseif (Test-McMapping -InputObject $install) {
                Remove-McObjectProperty -InputObject $install -Name 'root'
                if (@(Get-McPropertyEntries -InputObject $install).Count -eq 0) {
                    Remove-McObjectProperty -InputObject $observed -Name 'install'
                }
            }
            else {
                Remove-McObjectProperty -InputObject $observed -Name 'install'
            }
        }
    }

    Set-McObjectProperty -InputObject $observed -Name 'verification' -Value 'unverified'
    Set-McObjectProperty -InputObject $observed -Name 'verification_provider' -Value 'canonical-migration'
    Set-McObjectProperty -InputObject $observed -Name 'verification_reason' -Value 'collector-process-only-path'
    return $copy
}

function Merge-McProjects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ContextRoot,

        [Parameter(Mandatory)]
        [object]$ProjectIndex,

        [AllowNull()]
        [object[]]$Candidates,

        [AllowNull()]
        [System.Collections.Generic.List[string]]$RemovedFiles,

        [AllowNull()]
        [System.Collections.Generic.List[object]]$DemotedProjects
    )

    $projectRoot = Join-Path $ContextRoot 'projects'
    [void](New-Item -ItemType Directory -Path $projectRoot -Force)
    if ($null -eq $RemovedFiles) { $RemovedFiles = [System.Collections.Generic.List[string]]::new() }
    if ($null -eq $DemotedProjects) { $DemotedProjects = [System.Collections.Generic.List[object]]::new() }
    $repoRoot = Get-McRepoRoot -Path $ContextRoot
    $rootPolicies = @(Get-McProjectRootPolicies -RepoRoot $repoRoot)
    $records = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($file in @(Get-ChildItem -LiteralPath $projectRoot -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('_template.json', 'index.json') })) {
        $record = Read-McCanonicalJsonOrThrow -Path $file.FullName
        if (-not (Test-McMapping -InputObject $record)) { continue }
        $id = [string](Get-McObjectPropertyOrNull -InputObject $record -Name 'id')
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $observed = Get-McObjectPropertyOrNull -InputObject $record -Name 'observed'
            $localPath = [string](Get-McObjectPropertyOrNull -InputObject $observed -Name 'local_path')
            if (-not [string]::IsNullOrWhiteSpace($localPath)) {
                $policy = Get-McProjectRootPolicyForPath -Path $localPath -Policies $rootPolicies
                $demotable = [string]$policy.kind -in @('sdk-root', 'tool-root', 'cache-root', 'vendor-root')
                if ($demotable -and -not (Test-McProjectCuratedIntent -Record $record)) {
                    $recordFile = 'context/projects/{0}' -f $file.Name
                    if (-not $RemovedFiles.Contains($recordFile)) { [void]$RemovedFiles.Add($recordFile) }
                    [void]$DemotedProjects.Add([pscustomobject][ordered]@{
                            id             = $id
                            path           = $localPath
                            classification = [string]$policy.kind
                            reason         = 'historical-canonical-record-under-non-project-root'
                        })
                    continue
                }
            }
            $records[$id] = $record
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
                curated = [pscustomobject][ordered]@{}
            }
        }
        if ($null -ne $existing) {
            Set-McObjectProperty -InputObject $record -Name 'observed' -Value (Merge-McObservedObject -Previous $record.observed -Current $candidate.observed)
            if (-not [string]::IsNullOrWhiteSpace([string]$candidate.name_hint)) { Set-McObjectProperty -InputObject $record -Name 'name' -Value ([string]$candidate.name_hint) }
        }
        $records[$id] = $record
    }

    $indexRefs = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($records.Values | Sort-Object { [string]$_.id })) {
        [void]$indexRefs.Add([pscustomobject][ordered]@{
            id = [string]$record.id
            name = [string]$record.name
            path = [string]$record.observed.local_path
            context_file = ('context/projects/{0}' -f (Get-McProjectRecordFileName -Id ([string]$record.id)))
        })
        Write-McJson -Path (Join-Path $projectRoot (Get-McProjectRecordFileName -Id ([string]$record.id))) -InputObject $record
    }
    foreach ($removedFile in @($RemovedFiles)) {
        $stagedFile = Join-Path $ContextRoot ($removedFile -replace '^context[\\/]', '')
        $stagedFile = [System.IO.Path]::GetFullPath($stagedFile)
        if (Test-Path -LiteralPath $stagedFile -PathType Leaf) {
            Remove-Item -LiteralPath $stagedFile -Force
        }
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
    return @($map.Values | Sort-Object `
        @{ Expression = { [string]$_.from } },
        @{ Expression = { [string]$_.relation } },
        @{ Expression = { [string]$_.to } })
}

function Get-McAuditClosureCount {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) { return 0 }
    if ($InputObject -is [byte] -or
        $InputObject -is [sbyte] -or
        $InputObject -is [int16] -or
        $InputObject -is [uint16] -or
        $InputObject -is [int32] -or
        $InputObject -is [uint32] -or
        $InputObject -is [int64] -or
        $InputObject -is [uint64] -or
        $InputObject -is [single] -or
        $InputObject -is [double] -or
        $InputObject -is [decimal]) {
        $number = 0L
        if ([long]::TryParse([string]$InputObject, [ref]$number)) {
            return [Math]::Max(0L, $number)
        }
        return 0
    }
    if ($InputObject -is [string]) {
        if ([string]::IsNullOrWhiteSpace($InputObject)) { return 0 }
        return 1
    }
    return @($InputObject | Where-Object { $null -ne $_ }).Count
}

function ConvertTo-McAuditClosureProjection {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [string]$Source = 'unknown',

        [string]$UnavailableReason
    )

    $summary = Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'summary'
    $declaredState = [string](Get-McObjectPropertyOrNull -InputObject $summary -Name 'state')
    $conflictCount = Get-McAuditClosureCount -InputObject (Get-McObjectPropertyOrNull -InputObject $summary -Name 'conflicts')
    $canonicalUnknownCount = Get-McAuditClosureCount -InputObject (Get-McObjectPropertyOrNull -InputObject $summary -Name 'canonical_unknowns')
    $acceptedUnknownCount = Get-McAuditClosureCount -InputObject (Get-McObjectPropertyOrNull -InputObject $summary -Name 'accepted_unknowns')
    $hasExplicitOpenUnknowns = $false
    if ($null -ne $summary) {
        if ($summary -is [System.Collections.IDictionary]) {
            $hasExplicitOpenUnknowns = $summary.Contains('open_unknowns')
        }
        else {
            $hasExplicitOpenUnknowns = $null -ne $summary.PSObject.Properties['open_unknowns']
        }
    }
    $openUnknownCount = if ($hasExplicitOpenUnknowns) {
        Get-McAuditClosureCount -InputObject (Get-McObjectPropertyOrNull -InputObject $summary -Name 'open_unknowns')
    }
    else {
        $canonicalUnknownCount
    }
    $candidateUnknownCount = Get-McAuditClosureCount -InputObject (Get-McObjectPropertyOrNull -InputObject $summary -Name 'local_candidate_unknowns')
    $unresolvedCount = Get-McAuditClosureCount -InputObject (Get-McObjectPropertyOrNull -InputObject $summary -Name 'unresolved')
    $entries = Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'entries'
    foreach ($entry in @($entries | Where-Object { $null -ne $_ })) {
        if ([string](Get-McObjectPropertyOrNull -InputObject $entry -Name 'status') -ieq 'unresolved') {
            $unresolvedCount++
        }
    }

    $hasInput = $null -ne $InputObject
    $hasBlockingFindings = ($conflictCount -gt 0) -or ($openUnknownCount -gt 0) -or ($unresolvedCount -gt 0)
    $state = if ($hasInput -and $declaredState -ieq 'verified' -and -not $hasBlockingFindings) { 'verified' } else { 'partial' }
    $reason = if (-not [string]::IsNullOrWhiteSpace($UnavailableReason)) {
        $UnavailableReason
    }
    elseif (-not $hasInput) {
        'missing'
    }
    elseif ($state -eq 'verified') {
        $null
    }
    elseif ($hasBlockingFindings) {
        'blocking_findings'
    }
    else {
        'declared_partial'
    }

    return [pscustomobject][ordered]@{
        state = $state
        source = $Source
        generated_at = Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'generated_at'
        reason = $reason
        blocking = [pscustomobject][ordered]@{
            conflict_count = $conflictCount
            canonical_unknown_count = $canonicalUnknownCount
            accepted_unknown_count = $acceptedUnknownCount
            open_unknown_count = $openUnknownCount
            unresolved_entry_count = $unresolvedCount
            local_candidate_unknown_count = $candidateUnknownCount
        }
    }
}

function Get-McAuditClosureProjection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $path = Join-Path $RepoRoot '.local\audit-closure.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return ConvertTo-McAuditClosureProjection -Source '.local/audit-closure.json' -UnavailableReason 'missing'
    }

    try {
        $closure = Read-McJson -Path $path
        return ConvertTo-McAuditClosureProjection -InputObject $closure -Source '.local/audit-closure.json'
    }
    catch {
        return ConvertTo-McAuditClosureProjection -Source '.local/audit-closure.json' -UnavailableReason 'invalid'
    }
}

function Update-McPublishedStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Status,

        [Parameter(Mandatory)]
        [object]$Diagnostics,

        [Parameter(Mandatory)]
        [string]$Mode,

        [AllowNull()]
        [object]$AuditClosure,

        [switch]$PublishHeartbeat
    )

    $summary = ConvertTo-McPublishedProviderSummary -Providers $Diagnostics.providers
    $previous = Get-McObjectPropertyOrNull -InputObject $Status -Name 'published_verification'
    $previousSummary = if ($null -ne $previous) { @($previous.provider_summary | ForEach-Object { "{0}:{1}" -f $_.provider, $_.health } | Sort-Object) } else { @() }
    $newSummary = @($summary | ForEach-Object { "{0}:{1}" -f $_.provider, $_.health } | Sort-Object)
    $changed = ([string]$Mode -ne [string](Get-McObjectPropertyOrNull -InputObject $previous -Name 'mode')) -or ((ConvertTo-McJsonText -InputObject $previousSummary) -ne (ConvertTo-McJsonText -InputObject $newSummary))
    $previousVerifiedAt = Get-McObjectPropertyOrNull -InputObject $previous -Name 'verified_at'
    if ($PublishHeartbeat -or $changed -or [string]::IsNullOrWhiteSpace([string]$previousVerifiedAt)) {
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
    $providerState = if ($Diagnostics.overall_health -eq 'success') { 'verified' } else { 'partial' }
    $auditProjection = if ($null -ne $AuditClosure) {
        $AuditClosure
    }
    else {
        ConvertTo-McAuditClosureProjection -Source '.local/audit-closure.json' -UnavailableReason 'not_supplied'
    }
    $publishedState = if ($providerState -eq 'verified' -and $auditProjection.state -eq 'verified') { 'verified' } else { 'partial' }
    Set-McObjectProperty -InputObject $Status -Name 'provider_state' -Value $providerState
    Set-McObjectProperty -InputObject $Status -Name 'audit_closure' -Value $auditProjection
    Set-McObjectProperty -InputObject $Status -Name 'state' -Value $publishedState
    $Status.published_verification = [pscustomobject][ordered]@{
        mode = $Mode
        verified_at = $verifiedAt
        provider_summary = $summary
    }
    return $Status
}

function Merge-McConfigProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ContextRoot,

        [AllowNull()]
        [object[]]$Profiles,

        [AllowNull()]
        [object[]]$ProfileStates,

        [AllowNull()]
        [object]$McpInventory
    )

    $configRoot = Join-Path $ContextRoot 'configs'
    $aiRoot = Join-Path $configRoot 'ai'
    if (@($Profiles).Count -eq 0 -and @($ProfileStates).Count -eq 0 -and $null -eq $McpInventory -and -not (Test-Path -LiteralPath $configRoot -PathType Container)) {
        return
    }

    [void](New-Item -ItemType Directory -Path $aiRoot -Force)

    $freshTools = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($profile in @($Profiles | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_.tool) })) {
        $tool = [string]$profile.tool
        if ($tool -cnotmatch '^[a-z0-9][a-z0-9._-]*$') { continue }
        $path = Join-Path $aiRoot ("{0}.json" -f $tool)
        $record = Copy-McJsonObject -InputObject $profile
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $existing = Read-McCanonicalJsonOrThrow -Path $path
            $existingCurated = Get-McObjectPropertyOrNull -InputObject $existing -Name 'curated'
            if ($null -ne $existingCurated) {
                Set-McObjectProperty -InputObject $record -Name 'curated' -Value (Copy-McJsonObject -InputObject $existingCurated)
            }
        }
        Write-McJson -Path $path -InputObject $record
        [void]$freshTools.Add($tool)
    }

    # A confirmed source absence downgrades the last-known profile to stale so
    # it is never mistaken for current configuration. A parser/provider failure
    # (state 'failed') deliberately keeps the previous record untouched.
    foreach ($state in @($ProfileStates | Where-Object { $null -ne $_ -and [string]$_.state -eq 'source-missing' })) {
        $tool = [string]$state.tool
        if ([string]::IsNullOrWhiteSpace($tool) -or $freshTools.Contains($tool)) { continue }
        if ($tool -cnotmatch '^[a-z0-9][a-z0-9._-]*$') { continue }
        $path = Join-Path $aiRoot ("{0}.json" -f $tool)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $existing = Read-McCanonicalJsonOrThrow -Path $path
        $observed = Get-McObjectPropertyOrNull -InputObject $existing -Name 'observed'
        if (-not (Test-McMapping -InputObject $observed)) { continue }
        Set-McObjectProperty -InputObject $observed -Name 'source_state' -Value 'stale'
        Set-McObjectProperty -InputObject $observed -Name 'source_state_reason' -Value 'config source confirmed absent during scan'
        Write-McJson -Path $path -InputObject $existing
    }

    if ($null -ne $McpInventory) {
        $mcpPath = Join-Path $configRoot 'mcp.json'
        $mcpRecord = Copy-McJsonObject -InputObject $McpInventory
        if (Test-Path -LiteralPath $mcpPath -PathType Leaf) {
            $existingMcp = Read-McCanonicalJsonOrThrow -Path $mcpPath
            $existingCurated = Get-McObjectPropertyOrNull -InputObject $existingMcp -Name 'curated'
            if ($null -ne $existingCurated) {
                Set-McObjectProperty -InputObject $mcpRecord -Name 'curated' -Value (Copy-McJsonObject -InputObject $existingCurated)
            }
        }
        Write-McJson -Path $mcpPath -InputObject $mcpRecord
    }

    $modules = [System.Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem -LiteralPath $aiRoot -File -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $record = Read-McCanonicalJsonOrThrow -Path $file.FullName
        $module = [ordered]@{
            path = "ai/{0}" -f $file.Name
            tool = [string](Get-McObjectPropertyOrNull -InputObject $record -Name 'tool')
            kind = [string](Get-McObjectPropertyOrNull -InputObject $record -Name 'kind')
        }
        $moduleSourceState = [string](Get-McObjectPropertyOrNull -InputObject (Get-McObjectPropertyOrNull -InputObject $record -Name 'observed') -Name 'source_state')
        if (-not [string]::IsNullOrWhiteSpace($moduleSourceState)) { $module['source_state'] = $moduleSourceState }
        [void]$modules.Add([pscustomobject]$module)
    }
    if (Test-Path -LiteralPath (Join-Path $configRoot 'mcp.json') -PathType Leaf) {
        [void]$modules.Add([pscustomobject][ordered]@{
            path = 'mcp.json'
            tool = 'multi'
            kind = 'mcp-inventory'
        })
    }

    $index = [pscustomobject][ordered]@{
        schema_version = 1
        meta           = [pscustomobject][ordered]@{ state = 'observed' }
        policy         = [pscustomobject][ordered]@{
            privacy_model  = 'allowlist-projection'
            refresh_policy = 'routine-core-scan'
            removal_policy = 'explicit-cleanup-only'
        }
        modules        = @($modules)
    }
    Write-McJson -Path (Join-Path $configRoot 'index.json') -InputObject $index
}

function Invoke-McReconciliation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RunContext,

        [Parameter(Mandatory)]
        [object]$CollectionResult,

        [switch]$PublishHeartbeat
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

    Merge-McConfigProfiles -ContextRoot $contextRoot -Profiles @((Get-McObjectPropertyOrNull -InputObject $observations -Name 'configs').profiles) -ProfileStates @((Get-McObjectPropertyOrNull -InputObject (Get-McObjectPropertyOrNull -InputObject $observations -Name 'configs') -Name 'profile_states')) -McpInventory (Get-McObjectPropertyOrNull -InputObject (Get-McObjectPropertyOrNull -InputObject $observations -Name 'configs') -Name 'mcp')

    $projectIndexPath = Join-Path $contextRoot 'projects\index.json'
    $projectIndex = Read-McJson -Path $projectIndexPath
    $demotedProjects = [System.Collections.Generic.List[object]]::new()
    $projectIndex = Merge-McProjects -ContextRoot $contextRoot -ProjectIndex $projectIndex -Candidates @($observations.projects) -RemovedFiles $RunContext.proposed_deletions -DemotedProjects $demotedProjects
    Write-McJson -Path $projectIndexPath -InputObject $projectIndex

    if ($demotedProjects.Count -gt 0) {
        $localDiagnostics = Read-McJson -Path $RunContext.local_diagnostics_path
        Set-McObjectProperty -InputObject $localDiagnostics -Name 'project_reconciliation' -Value ([pscustomobject][ordered]@{
                demoted_count = $demotedProjects.Count
                demoted       = @($demotedProjects)
            })
        Write-McJson -Path $RunContext.local_diagnostics_path -InputObject $localDiagnostics
    }

    $relationshipsPath = Join-Path $contextRoot 'relationships.json'
    $relationships = Read-McJson -Path $relationshipsPath
    $demotedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($demoted in @($demotedProjects)) { [void]$demotedIds.Add([string]$demoted.id) }
    $previousRelationships = @($relationships.relationships | Where-Object { -not $demotedIds.Contains([string]$_.from) -and -not $demotedIds.Contains([string]$_.to) })
    $currentRelationships = @($observations.relationships | Where-Object { -not $demotedIds.Contains([string]$_.from) -and -not $demotedIds.Contains([string]$_.to) })
    $mergedRelationships = [System.Collections.Generic.List[object]]::new()
    foreach ($relationship in @(Merge-McRelationships -Previous $previousRelationships -Current $currentRelationships)) {
        if ($null -ne $relationship) { [void]$mergedRelationships.Add($relationship) }
    }
    Set-McObjectProperty -InputObject $relationships -Name 'relationships' -Value $mergedRelationships
    Write-McJson -Path $relationshipsPath -InputObject $relationships

    $statusPath = Join-Path $contextRoot 'status.json'
    $status = Read-McJson -Path $statusPath
    $auditClosure = Get-McAuditClosureProjection -RepoRoot $RunContext.repo_root
    $status = Update-McPublishedStatus -Status $status -Diagnostics $CollectionResult.diagnostics -Mode $RunContext.mode -AuditClosure $auditClosure -PublishHeartbeat:$PublishHeartbeat
    Write-McJson -Path $statusPath -InputObject $status

    return [pscustomobject][ordered]@{
        run_context = $RunContext
        proposed_context = $contextRoot
        proposed_current = $RunContext.proposed_current
        diagnostics = $CollectionResult.diagnostics
    }
}
