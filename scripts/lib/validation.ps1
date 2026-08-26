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
        if ([string]$entry.Name -ceq $Name) {
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
        if ([string]$entry.Name -ceq $Name) {
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
        foreach ($name in @('present', 'version', 'executable')) {
            if (Test-McContractProperty -InputObject $observed -Name $name) {
                Assert-McContractScalar -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name $name) -Path ("{0}.observed.{1}" -f $Path, $name)
            }
        }
        Assert-McContractMapping -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name 'install') -Path ("{0}.observed.install" -f $Path)
        foreach ($name in @('command_resolution', 'alternative_installations', 'config_paths', 'data_paths', 'evidence')) {
            Assert-McContractSequence -Findings $Findings -Value (Get-McContractProperty -InputObject $observed -Name $name) -Path ("{0}.observed.{1}" -f $Path, $name)
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
            if (Test-McLiteralUserProfilePath -Text $raw) {
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
                }
            }
        }
        catch {
            Add-McValidationFinding -Findings $findings -Severity error -Code 'invalid_project_index' -Message (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message) -Path $projectIndexPath
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
