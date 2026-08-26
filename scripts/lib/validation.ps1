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

            if ($file -match '\\software\\[^\\]+\.json$' -and $file -notmatch '\\software\\index\.json$') {
                $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($item in @($document.software)) {
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
