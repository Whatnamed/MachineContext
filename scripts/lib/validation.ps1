Set-StrictMode -Version Latest

function Add-McValidationFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [ValidateSet('error', 'warning')]
        [string]$Severity,

        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Path
    )

    [void]$Findings.Add([pscustomobject][ordered]@{
        severity = $Severity
        code = $Code
        message = $Message
        path = $Path
    })
}

function Test-McContractProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-McMapping -InputObject $InputObject)) {
        return $false
    }

    foreach ($entry in (Get-McPropertyEntries -InputObject $InputObject)) {
        if ([string]$entry.Name -ieq $Name) {
            return $true
        }
    }
    return $false
}

function Get-McContractProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Test-McMapping -InputObject $InputObject)) {
        return $null
    }

    foreach ($entry in (Get-McPropertyEntries -InputObject $InputObject)) {
        if ([string]$entry.Name -ieq $Name) {
            Write-Output -NoEnumerate -InputObject $entry.Value
            return
        }
    }
    return $null
}

function Assert-McContractMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Findings,

        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Required
    )

    if ($null -eq $Value -and -not $Required) {
        return
    }

    if (-not (Test-McMapping -InputObject $Value)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'contract_type_mismatch' -Message 'Expected a mapping/object value.' -Path $Path
    }
}

function Assert-McContractSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Findings,

        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$Required
    )

    if ($null -eq $Value -and -not $Required) {
        return
    }

    if (-not (Test-McSequence -InputObject $Value)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'contract_type_mismatch' -Message 'Expected a sequence/array value.' -Path $Path
    }
}

function Assert-McContractScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Findings,

        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McScalar -InputObject $Value)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'contract_type_mismatch' -Message 'Expected a scalar value.' -Path $Path
    }
}

function Validate-McVisualStudioWorkload {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McMapping -InputObject $Value)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'visual_studio_workload_type' -Message 'Visual Studio workload observation must be a mapping/object.' -Path $Path
        return
    }

    $workloadId = Get-McContractProperty -InputObject $Value -Name 'workload_id'
    Assert-McContractScalar -Findings $Findings -Value $workloadId -Path ("{0}.workload_id" -f $Path)
    if ([string]$workloadId -ne 'Microsoft.VisualStudio.Workload.NativeDesktop') {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'visual_studio_workload_id' -Message 'Visual Studio workload observation must identify the Native Desktop workload.' -Path ("{0}.workload_id" -f $Path)
    }

    $verification = Get-McContractProperty -InputObject $Value -Name 'verification'
    Assert-McContractScalar -Findings $Findings -Value $verification -Path ("{0}.verification" -f $Path)
    $verificationText = [string]$verification
    if ($verificationText -notin @('verified-present', 'verified-absent', 'unverified', 'stale')) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'visual_studio_workload_verification' -Message 'Visual Studio workload verification state is not recognized.' -Path ("{0}.verification" -f $Path)
    }

    $paths = Get-McContractProperty -InputObject $Value -Name 'installation_paths'
    $pathsProperty = Test-McContractProperty -InputObject $Value -Name 'installation_paths'
    if ($pathsProperty) {
        Assert-McContractSequence -Findings $Findings -Value $paths -Path ("{0}.installation_paths" -f $Path)
    }
    $pathCount = if (Test-McSequence -InputObject $paths) { @($paths).Count } else { 0 }
    $presentProperty = Test-McContractProperty -InputObject $Value -Name 'present'
    $present = Get-McContractProperty -InputObject $Value -Name 'present'
    if ($presentProperty) {
        Assert-McContractScalar -Findings $Findings -Value $present -Path ("{0}.present" -f $Path)
    }

    if ($verificationText -eq 'verified-present' -and ($present -ne $true -or -not $pathsProperty -or $pathCount -eq 0)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'visual_studio_workload_present_contract' -Message 'verified-present Native Desktop workload must have present=true and at least one installation path.' -Path $Path
    }
    elseif ($verificationText -eq 'verified-absent' -and ($present -ne $false -or -not $pathsProperty -or $pathCount -ne 0)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'visual_studio_workload_absent_contract' -Message 'verified-absent Native Desktop workload must have present=false and no installation paths.' -Path $Path
    }
    elseif ($verificationText -in @('unverified', 'stale') -and $present -eq $false) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'visual_studio_workload_unsafe_absence' -Message 'Unverified or stale Native Desktop workload must not claim present=false.' -Path ("{0}.present" -f $Path)
    }
}

function Validate-McSoftwareRecord {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Record,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McMapping -InputObject $Record)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'contract_type_mismatch' -Message 'Software record must be a mapping/object.' -Path $Path
        return
    }

    foreach ($name in @('id', 'kind', 'name')) {
        if (Test-McContractProperty -InputObject $Record -Name $name) {
            Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name $name) -Path ("{0}.{1}" -f $Path, $name)
        }
    }

    foreach ($name in @('observed', 'curated')) {
        $sectionPath = "{0}.{1}" -f $Path, $name
        Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name $name) -Path $sectionPath -Required
    }

    $observed = Get-McContractProperty -InputObject $Record -Name 'observed'
    if (Test-McMapping -InputObject $observed) {
        foreach ($name in @('present', 'version', 'executable', 'distribution_version')) {
            if (Test-McContractProperty -InputObject $observed -Name $name) {
                Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name $name) -Path ("{0}.observed.{1}" -f $Path, $name)
            }
        }
        Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name 'install') -Path ("{0}.observed.install" -f $Path)
        foreach ($name in @('command_resolution', 'alternative_installations', 'config_paths', 'data_paths', 'evidence')) {
            Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name $name) -Path ("{0}.observed.{1}" -f $Path, $name)
        }
        if ([string](Get-McContractProperty -InputObject $Record -Name 'id') -eq 'visual-studio' -and (Test-McContractProperty -InputObject $observed -Name 'desktop_cpp_workload')) {
            Validate-McVisualStudioWorkload -Value (Get-McContractProperty -InputObject $observed -Name 'desktop_cpp_workload') -Findings $Findings -Path ("{0}.observed.desktop_cpp_workload" -f $Path)
        }
    }

    $curated = Get-McContractProperty -InputObject $Record -Name 'curated'
    if (Test-McMapping -InputObject $curated) {
        Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $curated -Name 'constraints') -Path ("{0}.curated.constraints" -f $Path)
    }
}

function Validate-McProjectRecord {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Record,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McMapping -InputObject $Record)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'contract_type_mismatch' -Message 'Project record must be a mapping/object.' -Path $Path
        return
    }

    foreach ($name in @('id', 'name')) {
        if (Test-McContractProperty -InputObject $Record -Name $name) {
            Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name $name) -Path ("{0}.{1}" -f $Path, $name)
        }
    }
    foreach ($name in @('observed', 'curated')) {
        $sectionPath = "{0}.{1}" -f $Path, $name
        Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name $name) -Path $sectionPath -Required
    }

    $observed = Get-McContractProperty -InputObject $Record -Name 'observed'
    if (Test-McMapping -InputObject $observed) {
        foreach ($name in @('local_path', 'repository', 'package_manager', 'workspace_type')) {
            if (Test-McContractProperty -InputObject $observed -Name $name) {
                Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name $name) -Path ("{0}.observed.{1}" -f $Path, $name)
            }
        }
        foreach ($name in @('runtime_refs', 'package_manager_refs', 'tool_refs', 'service_refs', 'manifests', 'local_endpoints', 'evidence')) {
            Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name $name) -Path ("{0}.observed.{1}" -f $Path, $name)
        }
        Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name 'commands') -Path ("{0}.observed.commands" -f $Path)
    }

    $curated = Get-McContractProperty -InputObject $Record -Name 'curated'
    if (Test-McMapping -InputObject $curated) {
        Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $curated -Name 'constraints') -Path ("{0}.curated.constraints" -f $Path)
    }
}

function Validate-McConfigProfileRecord {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Record,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McMapping -InputObject $Record)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'contract_type_mismatch' -Message 'Config profile record must be a mapping/object.' -Path $Path
        return
    }

    foreach ($name in @('id', 'tool', 'kind')) {
        if (Test-McContractProperty -InputObject $Record -Name $name) {
            Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name $name) -Path ("{0}.{1}" -f $Path, $name)
        }
    }
    if ([string](Get-McContractProperty -InputObject $Record -Name 'kind') -ne 'ai-config-profile') {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'config_profile_kind' -Message 'Config profile records must declare kind ai-config-profile.' -Path ("{0}.kind" -f $Path)
    }
    $id = [string](Get-McContractProperty -InputObject $Record -Name 'id')
    if (-not (Test-McSafeId -Id $id)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'unsafe_id' -Message 'Config profile id is not stable/safe.' -Path ("{0}.id" -f $Path)
    }

    Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name 'source') -Path ("{0}.source" -f $Path) -Required
    $source = Get-McContractProperty -InputObject $Record -Name 'source'
    if (Test-McMapping -InputObject $source) {
        Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $source -Name 'files') -Path ("{0}.source.files" -f $Path)
    }

    foreach ($name in @('observed', 'curated')) {
        Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name $name) -Path ("{0}.{1}" -f $Path, $name) -Required
    }

    $observed = Get-McContractProperty -InputObject $Record -Name 'observed'
    if (Test-McMapping -InputObject $observed) {
        Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name 'value_basis') -Path ("{0}.observed.value_basis" -f $Path)
        $sourceState = [string](Get-McContractProperty -InputObject $observed -Name 'source_state')
        if (-not [string]::IsNullOrWhiteSpace($sourceState) -and $sourceState -notin @('current', 'stale')) {
            Add-McValidationFinding -Findings $Findings -Severity error -Code 'config_profile_source_state' -Message 'Config profile source_state must be current or stale.' -Path ("{0}.observed.source_state" -f $Path)
        }
        Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name 'source_state_reason') -Path ("{0}.observed.source_state_reason" -f $Path)
        $projection = Get-McContractProperty -InputObject $observed -Name 'projection'
        if ($null -ne $projection) {
            Assert-McContractMapping -Findings $Findings -Value $projection -Path ("{0}.observed.projection" -f $Path)
        }
        foreach ($name in @('credential_env_names', 'redactions', 'evidence')) {
            Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name $name) -Path ("{0}.observed.{1}" -f $Path, $name)
        }
        if (Test-McContractProperty -InputObject $observed -Name 'credential_env_names') {
            $envIndex = 0
            foreach ($envName in (Get-McContractProperty -InputObject $observed -Name 'credential_env_names')) {
                if (-not (Test-McEnvVarNameShape -Value ([string]$envName))) {
                    Add-McValidationFinding -Findings $Findings -Severity error -Code 'config_invalid_env_name' -Message 'credential_env_names entries must be environment-variable names.' -Path ("{0}.observed.credential_env_names[{1}]" -f $Path, $envIndex)
                }
                $envIndex++
            }
        }
    }
}

function Validate-McMcpInventoryRecord {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Record,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McMapping -InputObject $Record)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'contract_type_mismatch' -Message 'MCP inventory record must be a mapping/object.' -Path $Path
        return
    }

    if ([string](Get-McContractProperty -InputObject $Record -Name 'kind') -ne 'mcp-inventory') {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'mcp_inventory_kind' -Message 'MCP inventory records must declare kind mcp-inventory.' -Path ("{0}.kind" -f $Path)
    }
    Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name 'observed') -Path ("{0}.observed" -f $Path) -Required
    Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name 'curated') -Path ("{0}.curated" -f $Path) -Required

    $observed = Get-McContractProperty -InputObject $Record -Name 'observed'
    if (Test-McMapping -InputObject $observed) {
        Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name 'servers') -Path ("{0}.observed.servers" -f $Path)
        Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name 'redactions') -Path ("{0}.observed.redactions" -f $Path)
        $serverIndex = 0
        foreach ($server in @(Get-McContractProperty -InputObject $observed -Name 'servers')) {
            $serverPath = "{0}.observed.servers[{1}]" -f $Path, $serverIndex
            if (Test-McMapping -InputObject $server) {
                foreach ($name in @('tool', 'scope', 'name', 'transport', 'command', 'url')) {
                    if (Test-McContractProperty -InputObject $server -Name $name) {
                        Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $server -Name $name) -Path ("{0}.{1}" -f $serverPath, $name)
                    }
                }
                foreach ($name in @('args', 'env_names')) {
                    Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $server -Name $name) -Path ("{0}.{1}" -f $serverPath, $name)
                }
            }
            $serverIndex++
        }
    }
}

function Add-McConfigSensitiveKeyFindings {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Document,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    foreach ($finding in (Get-McSensitiveConfigKeyFindings -InputObject $Document)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'config_sensitive_key' -Message 'Config projection must not contain a credential-named property.' -Path ("{0}:{1}" -f $Path, $finding.path)
    }
}

function Validate-McMachineRecord {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Record,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McMapping -InputObject $Record)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'contract_type_mismatch' -Message 'Machine record must be a mapping/object.' -Path $Path
        return
    }

    foreach ($name in @('system', 'hardware', 'paths', 'environment')) {
        if (Test-McContractProperty -InputObject $Record -Name $name) {
            Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name $name) -Path ("{0}.{1}" -f $Path, $name) -Required
        }
    }
    foreach ($name in @('storage', 'shells', 'command_resolution', 'constraints')) {
        Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name $name) -Path ("{0}.{1}" -f $Path, $name)
    }

    $paths = Get-McContractProperty -InputObject $Record -Name 'paths'
    if (Test-McMapping -InputObject $paths) {
        foreach ($name in @('machine_path', 'user_path', 'persistent_effective_path', 'path_entries', 'known_roots')) {
            Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $paths -Name $name) -Path ("{0}.paths.{1}" -f $Path, $name)
        }
    }
    $environment = Get-McContractProperty -InputObject $Record -Name 'environment'
    if (Test-McMapping -InputObject $environment) {
        Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $environment -Name 'path_summary') -Path ("{0}.environment.path_summary" -f $Path)
    }
}

function Validate-McRelationship {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Record,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McMapping -InputObject $Record)) {
        Add-McValidationFinding -Findings $Findings -Severity error -Code 'contract_type_mismatch' -Message 'Relationship must be a mapping/object.' -Path $Path
        return
    }

    foreach ($name in @('from', 'relation', 'to', 'origin')) {
        if (Test-McContractProperty -InputObject $Record -Name $name) {
            Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name $name) -Path ("{0}.{1}" -f $Path, $name)
        }
    }
    Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $Record -Name 'evidence') -Path ("{0}.evidence" -f $Path)
}

function Add-McForbiddenMetadataFindings {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [object]$Findings,

        [string]$Path = '$'
    )

    if ($null -eq $InputObject) {
        return
    }

    if (Test-McMapping -InputObject $InputObject) {
        foreach ($entry in (Get-McPropertyEntries -InputObject $InputObject)) {
            $entryPath = "{0}.{1}" -f $Path, $entry.Name
            if ([string]$entry.Name -in @('SyncRoot', 'IsFixedSize', 'IsReadOnly', 'IsSynchronized', 'LongLength', 'Rank')) {
                Add-McValidationFinding -Findings $Findings -Severity error -Code 'dotnet_collection_metadata' -Message 'Canonical data must not contain .NET collection metadata properties.' -Path $entryPath
            }
            Add-McForbiddenMetadataFindings -InputObject $entry.Value -Findings $Findings -Path $entryPath
        }
        return
    }

    if (Test-McSequence -InputObject $InputObject) {
        $index = 0
        foreach ($item in $InputObject) {
            Add-McForbiddenMetadataFindings -InputObject $item -Findings $Findings -Path ("{0}[{1}]" -f $Path, $index)
            $index++
        }
    }
}

function Test-McLiteralUserProfilePath {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }
    $profile = [Environment]::GetEnvironmentVariable('USERPROFILE')
    if ([string]::IsNullOrWhiteSpace($profile)) {
        return $false
    }
    return $Text.IndexOf($profile.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

# Raw JSON text escapes backslashes ('C:\\Users\\...'), so a literal-profile
# check on raw text would never match a serialized Windows path; walk the
# decoded string values instead.
function Test-McDocumentContainsLiteralUserProfilePath {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [string]) { return (Test-McLiteralUserProfilePath -Text $InputObject) }
    if ($InputObject -is [System.Collections.IDictionary] -or $InputObject -is [pscustomobject]) {
        foreach ($entry in (Get-McPropertyEntries -InputObject $InputObject)) {
            if (Test-McDocumentContainsLiteralUserProfilePath -InputObject $entry.Value) { return $true }
        }
        return $false
    }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        foreach ($item in $InputObject) {
            if (Test-McDocumentContainsLiteralUserProfilePath -InputObject $item) { return $true }
        }
    }
    return $false
}

function Get-McKnownEntityIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ContextRoot
    )

    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in @(Get-ChildItem -LiteralPath (Join-Path $ContextRoot 'software') -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
        if ($path.Name -eq '_template.json') { continue }
        try {
            $document = Read-McJson -Path $path.FullName
            foreach ($item in @($document.software)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$item.id)) { [void]$ids.Add([string]$item.id) }
            }
        }
        catch {
        }
    }
    $indexPath = Join-Path $ContextRoot 'projects\index.json'
    if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
        try {
            $index = Read-McJson -Path $indexPath
            foreach ($item in @($index.projects)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$item.id)) { [void]$ids.Add([string]$item.id) }
            }
        }
        catch {
        }
    }
    $machinePath = Join-Path $ContextRoot 'machine.json'
    if (Test-Path -LiteralPath $machinePath -PathType Leaf) {
        try {
            $machine = Read-McJson -Path $machinePath
            foreach ($shell in @($machine.shells)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$shell.id)) { [void]$ids.Add([string]$shell.id) }
            }
        }
        catch {
        }
    }
    return $ids
}

function Invoke-McValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$ContextRoot = (Join-Path $RepoRoot 'context'),

        [string]$CurrentPath = (Join-Path $RepoRoot 'CURRENT.md')
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $jsonFiles = @(Get-McCanonicalFiles -RepoRoot $RepoRoot -ContextRoot $ContextRoot)
    if ($jsonFiles.Count -eq 0) {
        Add-McValidationFinding -Findings $findings -Severity error -Code 'no_canonical_files' -Message 'No canonical JSON files were found.' -Path $ContextRoot
    }

    foreach ($file in $jsonFiles) {
        try {
            $document = Read-McJson -Path $file
            if ($null -eq $document.schema_version) {
                Add-McValidationFinding -Findings $findings -Severity error -Code 'missing_schema_version' -Message 'Canonical JSON must declare schema_version.' -Path $file
            }

            $raw = [System.IO.File]::ReadAllText($file, [System.Text.UTF8Encoding]::new($false))
            $expected = ConvertTo-McJsonText -InputObject $document
            if ($raw -cne $expected) {
                Add-McValidationFinding -Findings $findings -Severity error -Code 'non_deterministic_json' -Message 'Canonical JSON is not in repository deterministic form.' -Path $file
            }

            foreach ($privacyFinding in (Get-McPrivacyFindingsInObject -InputObject $document)) {
                Add-McValidationFinding -Findings $findings -Severity error -Code ("privacy_{0}" -f $privacyFinding.code) -Message 'Potential secret or credential-bearing value detected.' -Path ("{0}:{1}" -f $file, $privacyFinding.source)
            }

            Add-McForbiddenMetadataFindings -InputObject $document -Findings $findings -Path '$'
            if (Test-McDocumentContainsLiteralUserProfilePath -InputObject $document) {
                Add-McValidationFinding -Findings $findings -Severity error -Code 'literal_user_path' -Message 'Canonical data must use normalized user paths such as %USERPROFILE%.' -Path $file
            }

            if ($file -match '\\software\\[^\\]+\.json$' -and $file -notmatch '\\software\\index\.json$') {
                if (Test-McContractProperty -InputObject $document -Name 'software') {
                    Assert-McContractSequence -Findings $findings -Value (Get-McContractProperty -InputObject $document -Name 'software') -Path "$file`:.software" -Required
                }
                $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $softwareIndex = 0
                foreach ($item in @($document.software)) {
                    Validate-McSoftwareRecord -Record $item -Findings $findings -Path ("{0}:$.software[{1}]" -f $file, $softwareIndex)
                    $softwareIndex++
                    if ([string]::IsNullOrWhiteSpace([string]$item.id)) {
                        Add-McValidationFinding -Findings $findings -Severity error -Code 'software_missing_id' -Message 'Software records require a stable id.' -Path $file
                        continue
                    }
                    if (-not (Test-McSafeId -Id ([string]$item.id))) {
                        Add-McValidationFinding -Findings $findings -Severity error -Code 'unsafe_id' -Message 'Software id is not stable/safe.' -Path $file
                    }
                    if (-not $ids.Add([string]$item.id)) {
                        Add-McValidationFinding -Findings $findings -Severity error -Code 'duplicate_software_id' -Message 'Software ids must be unique within a module.' -Path $file
                    }
                }
            }

            if ($file -match '\\machine\.json$') {
                Validate-McMachineRecord -Record $document -Findings $findings -Path $file
            }

            if ($file -match '\\projects\\[^\\]+\.json$' -and $file -notmatch '\\projects\\index\.json$') {
                Validate-McProjectRecord -Record $document -Findings $findings -Path $file
            }

            if ($file -match '\\configs\\ai\\[^\\]+\.json$') {
                Validate-McConfigProfileRecord -Record $document -Findings $findings -Path "$file`:$"
            }

            if ($file -match '\\configs\\mcp\.json$') {
                Validate-McMcpInventoryRecord -Record $document -Findings $findings -Path "$file`:$"
            }

            if ($file -match '\\configs\\') {
                Add-McConfigSensitiveKeyFindings -Document $document -Findings $findings -Path $file
            }

            if ($file -match '\\relationships\.json$') {
                Assert-McContractSequence -Findings $findings -Value (Get-McContractProperty -InputObject $document -Name 'relationships') -Path "$file`:.relationships" -Required
                $relationshipIndex = 0
                foreach ($relationship in @($document.relationships)) {
                    Validate-McRelationship -Record $relationship -Findings $findings -Path ("{0}:$.relationships[{1}]" -f $file, $relationshipIndex)
                    $relationshipIndex++
                }
            }
        }
        catch {
            Add-McValidationFinding -Findings $findings -Severity error -Code 'invalid_json' -Message (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message) -Path $file
        }
    }

    $projectIndexPath = Join-Path $ContextRoot 'projects\index.json'
    if (Test-Path -LiteralPath $projectIndexPath -PathType Leaf) {
        try {
            $projectIndex = Read-McJson -Path $projectIndexPath
            $projectIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($item in @($projectIndex.projects)) {
                if ([string]::IsNullOrWhiteSpace([string]$item.id)) {
                    Add-McValidationFinding -Findings $findings -Severity error -Code 'project_missing_id' -Message 'Project index records require a stable id.' -Path $projectIndexPath
                    continue
                }
                if (-not (Test-McSafeId -Id ([string]$item.id))) {
                    Add-McValidationFinding -Findings $findings -Severity error -Code 'unsafe_project_id' -Message 'Project id is not stable/safe.' -Path $projectIndexPath
                }
                if (-not $projectIds.Add([string]$item.id)) {
                    Add-McValidationFinding -Findings $findings -Severity error -Code 'duplicate_project_id' -Message 'Project ids must be unique.' -Path $projectIndexPath
                }
                if ([string]::IsNullOrWhiteSpace([string]$item.context_file)) {
                    Add-McValidationFinding -Findings $findings -Severity error -Code 'project_missing_context_file' -Message 'Project index item must reference a context file.' -Path $projectIndexPath
                }
                else {
                    $relative = ([string]$item.context_file -replace '/', '\') -replace '^context\\', ''
                    $recordPath = Join-Path $ContextRoot $relative
                    if (-not (Test-Path -LiteralPath $recordPath -PathType Leaf)) {
                        Add-McValidationFinding -Findings $findings -Severity error -Code 'broken_project_reference' -Message 'Project context_file does not exist.' -Path $projectIndexPath
                    }
                    else {
                        try {
                            $projectRecord = Read-McJson -Path $recordPath
                            $recordId = [string](Get-McContractProperty -InputObject $projectRecord -Name 'id')
                            if (-not [string]::IsNullOrWhiteSpace($recordId) -and $recordId -ine [string]$item.id) {
                                Add-McValidationFinding -Findings $findings -Severity error -Code 'project_id_mismatch' -Message 'Project index id must match the id of the referenced project record.' -Path $projectIndexPath
                            }
                        }
                        catch {
                            # Unreadable records are reported by the per-file loop
                            # as invalid_json; skip only the id comparison here.
                        }
                    }
                }
            }
        }
        catch {
            Add-McValidationFinding -Findings $findings -Severity error -Code 'invalid_project_index' -Message (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message) -Path $projectIndexPath
        }
    }

    # Index references must resolve: a registered module path that does not
    # exist means canonical data silently disappeared behind a valid-looking
    # index. Checks are forward-only (index -> file); unregistered files are
    # still covered by the recursive canonical scan above.
    foreach ($indexContract in @(
            [pscustomobject]@{ IndexPath = (Join-Path $ContextRoot 'software\index.json'); BaseDir = (Join-Path $ContextRoot 'software'); InvalidCode = 'invalid_software_index'; BrokenCode = 'broken_software_index_reference' },
            [pscustomobject]@{ IndexPath = (Join-Path $ContextRoot 'configs\index.json'); BaseDir = (Join-Path $ContextRoot 'configs'); InvalidCode = 'invalid_config_index'; BrokenCode = 'broken_config_index_reference' }
        )) {
        if (-not (Test-Path -LiteralPath $indexContract.IndexPath -PathType Leaf)) { continue }
        try {
            $indexDocument = Read-McJson -Path $indexContract.IndexPath
            foreach ($module in @($indexDocument.modules)) {
                $modulePath = [string](Get-McContractProperty -InputObject $module -Name 'path')
                if ([string]::IsNullOrWhiteSpace($modulePath)) {
                    Add-McValidationFinding -Findings $findings -Severity error -Code $indexContract.BrokenCode -Message 'Index module entry does not declare a path.' -Path $indexContract.IndexPath
                    continue
                }
                $moduleLocation = Join-Path $indexContract.BaseDir (([string]$modulePath) -replace '/', '\')
                if (-not (Test-Path -LiteralPath $moduleLocation -PathType Leaf)) {
                    Add-McValidationFinding -Findings $findings -Severity error -Code $indexContract.BrokenCode -Message 'Index references a module file that does not exist.' -Path ("{0}:{1}" -f $indexContract.IndexPath, $modulePath)
                }
            }
        }
        catch {
            Add-McValidationFinding -Findings $findings -Severity error -Code $indexContract.InvalidCode -Message (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message) -Path $indexContract.IndexPath
        }
    }

    $relationshipPath = Join-Path $ContextRoot 'relationships.json'
    if (Test-Path -LiteralPath $relationshipPath -PathType Leaf) {
        try {
            $relationships = Read-McJson -Path $relationshipPath
            $knownIds = Get-McKnownEntityIds -ContextRoot $ContextRoot
            foreach ($relationship in @($relationships.relationships)) {
                if ($null -eq $relationship) { continue }
                foreach ($side in @('from', 'to')) {
                    $id = [string]$relationship.$side
                    if (-not [string]::IsNullOrWhiteSpace($id) -and -not $knownIds.Contains($id)) {
                        Add-McValidationFinding -Findings $findings -Severity warning -Code 'unknown_relationship_reference' -Message ("Relationship {0} references an unregistered id." -f $side) -Path $relationshipPath
                    }
                }
            }
        }
        catch {
            Add-McValidationFinding -Findings $findings -Severity error -Code 'invalid_relationships' -Message (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message) -Path $relationshipPath
        }
    }

    if (Test-Path -LiteralPath $CurrentPath -PathType Leaf) {
        $currentRaw = [System.IO.File]::ReadAllText($CurrentPath, [System.Text.UTF8Encoding]::new($false))
        if ($currentRaw -notmatch '(?m)^> GENERATED VIEW') {
            Add-McValidationFinding -Findings $findings -Severity error -Code 'current_not_generated' -Message 'CURRENT.md must contain the generated-view marker.' -Path $CurrentPath
        }
        foreach ($privacyFinding in (Get-McPrivacyFindingsInText -Text $currentRaw -Source $CurrentPath)) {
            Add-McValidationFinding -Findings $findings -Severity error -Code ("privacy_{0}" -f $privacyFinding.code) -Message 'Potential secret or credential-bearing value detected.' -Path $CurrentPath
        }
        if (Test-McLiteralUserProfilePath -Text $currentRaw) {
            Add-McValidationFinding -Findings $findings -Severity error -Code 'literal_user_path' -Message 'Canonical views must use normalized user paths such as %USERPROFILE%.' -Path $CurrentPath
        }
    }
    else {
        Add-McValidationFinding -Findings $findings -Severity error -Code 'missing_current' -Message 'CURRENT.md is missing.' -Path $CurrentPath
    }

    $errors = @($findings | Where-Object severity -eq 'error')
    return [pscustomobject][ordered]@{
        ok = ($errors.Count -eq 0)
        errors = @($errors)
        warnings = @($findings | Where-Object severity -eq 'warning')
        findings = @($findings)
    }
}
