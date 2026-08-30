Set-StrictMode -Version Latest

# Deliberately not a wrapper over Get-McObjectPropertyOrNull: this variant
# guards on Test-McMapping and preserves single-element array values via
# Write-Output -NoEnumerate, which audit document checks rely on.
function Get-McAuditPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject -or -not (Test-McMapping -InputObject $InputObject)) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            Write-Output -NoEnumerate -InputObject $InputObject[$Name]
        }
        return
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
        Write-Output -NoEnumerate -InputObject $property.Value
    }
}

function Test-McAuditPropertyPresent {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject -or -not (Test-McMapping -InputObject $InputObject)) {
        return $false
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $InputObject.Contains($Name)
    }

    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function Add-McAuditReviewFinding {
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

function Test-McAuditStringList {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Errors,

        [Parameter(Mandatory)]
        [string]$Path
    )

    # PowerShell can expose an empty JSON array as $null in a property access;
    # treat that representation as an empty list while rejecting scalar values.
    if ($null -eq $Value) {
        return
    }

    if (-not (Test-McSequence -InputObject $Value)) {
        Add-McAuditReviewFinding -Findings $Errors -Severity error -Code 'audit_closure_type_mismatch' -Message 'Expected a string-list/array value.' -Path $Path
        return
    }

    $index = 0
    foreach ($item in @($Value)) {
        if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string]$item)) {
            Add-McAuditReviewFinding -Findings $Errors -Severity error -Code 'audit_closure_blank_list_item' -Message 'String-list items must be non-empty.' -Path ("{0}[{1}]" -f $Path, $index)
        }
        $index++
    }
}

function Test-McAuditSequenceProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Errors,

        [Parameter(Mandatory)]
        [string]$Path
    )

    # See Test-McAuditStringList for the empty-array/$null compatibility rule.
    if ($null -eq $Value) {
        return
    }

    if (-not (Test-McSequence -InputObject $Value)) {
        Add-McAuditReviewFinding -Findings $Errors -Severity error -Code 'audit_closure_type_mismatch' -Message 'Expected a sequence/array value.' -Path $Path
    }
}

function Test-McAuditClosureDocument {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [string]$Source = 'unknown'
    )

    $errors = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[object]]::new()
    $entryCount = 0
    $runIdCount = 0
    $projection = ConvertTo-McAuditClosureProjection -InputObject $InputObject -Source $Source

    if (-not (Test-McMapping -InputObject $InputObject)) {
        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_root_type_mismatch' -Message 'Audit closure root must be a JSON object.' -Path '$'
    }
    else {
        $schemaVersion = Get-McAuditPropertyValue -InputObject $InputObject -Name 'schema_version'
        $parsedSchemaVersion = 0
        $schemaVersionValid = [int]::TryParse([string]$schemaVersion, [ref]$parsedSchemaVersion)
        if (-not $schemaVersionValid -or $parsedSchemaVersion -ne 1) {
            Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_schema_version' -Message 'Audit closure schema_version must be 1.' -Path '$.schema_version'
        }

        $kind = [string](Get-McAuditPropertyValue -InputObject $InputObject -Name 'kind')
        if ($kind -cne 'initial-audit-closure') {
            Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_kind' -Message 'Audit closure kind must be initial-audit-closure.' -Path '$.kind'
        }

        $generatedAt = Get-McAuditPropertyValue -InputObject $InputObject -Name 'generated_at'
        if ($null -eq $generatedAt -or [string]::IsNullOrWhiteSpace([string]$generatedAt)) {
            Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_generated_at' -Message 'Audit closure generated_at must be present and non-empty.' -Path '$.generated_at'
        }

        $summary = Get-McAuditPropertyValue -InputObject $InputObject -Name 'summary'
        if (-not (Test-McMapping -InputObject $summary)) {
            Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_summary_type' -Message 'Audit closure summary must be a JSON object.' -Path '$.summary'
        }
        else {
            $summaryState = [string](Get-McAuditPropertyValue -InputObject $summary -Name 'state')
            if ($summaryState -notin @('partial', 'verified')) {
                Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_summary_state' -Message 'Audit closure summary.state must be partial or verified.' -Path '$.summary.state'
            }

            foreach ($field in @('conflicts', 'canonical_unknowns', 'accepted_unknowns', 'open_unknowns', 'verified_negative_facts', 'local_candidate_unknowns')) {
                if (-not (Test-McAuditPropertyPresent -InputObject $summary -Name $field)) {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_missing_summary_field' -Message ("Audit closure summary must contain '{0}'." -f $field) -Path ("$.summary.{0}" -f $field)
                    continue
                }
                Test-McAuditStringList -Value (Get-McAuditPropertyValue -InputObject $summary -Name $field) -Errors $errors -Path ("$.summary.{0}" -f $field)
            }

            if (Test-McAuditPropertyPresent -InputObject $summary -Name 'unresolved') {
                Test-McAuditStringList -Value (Get-McAuditPropertyValue -InputObject $summary -Name 'unresolved') -Errors $errors -Path '$.summary.unresolved'
            }

            if (Test-McAuditPropertyPresent -InputObject $summary -Name 'idempotency') {
                $idempotency = Get-McAuditPropertyValue -InputObject $summary -Name 'idempotency'
                if (-not (Test-McMapping -InputObject $idempotency)) {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_idempotency_type' -Message 'Audit closure summary.idempotency must be a JSON object.' -Path '$.summary.idempotency'
                }
            }
        }

        if (Test-McAuditPropertyPresent -InputObject $InputObject -Name 'run_ids') {
            $runIds = Get-McAuditPropertyValue -InputObject $InputObject -Name 'run_ids'
            if (-not (Test-McMapping -InputObject $runIds)) {
                Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_run_ids_type' -Message 'Audit closure run_ids must be a JSON object.' -Path '$.run_ids'
            }
            else {
                $runIdEntries = @(Get-McPropertyEntries -InputObject $runIds)
                $runIdCount = $runIdEntries.Count
                foreach ($entry in $runIdEntries) {
                    if ([string]::IsNullOrWhiteSpace([string]$entry.Name) -or [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_blank_run_id' -Message 'Audit closure run_ids keys and values must be non-empty.' -Path '$.run_ids'
                    }
                }
            }
        }

        if (-not (Test-McAuditPropertyPresent -InputObject $InputObject -Name 'entries')) {
            Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_missing_entries' -Message 'Audit closure entries must be present.' -Path '$.entries'
        }
        else {
            $entries = Get-McAuditPropertyValue -InputObject $InputObject -Name 'entries'
            Test-McAuditSequenceProperty -Value $entries -Errors $errors -Path '$.entries'
            if ($null -ne $entries -and (Test-McSequence -InputObject $entries)) {
                $entryCount = @($entries).Count
                $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                $entryIndex = 0
                foreach ($entry in @($entries)) {
                    $entryPath = "$.entries[{0}]" -f $entryIndex
                    if (-not (Test-McMapping -InputObject $entry)) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_entry_type' -Message 'Audit closure entries must contain JSON objects.' -Path $entryPath
                        $entryIndex++
                        continue
                    }

                    $entryId = [string](Get-McAuditPropertyValue -InputObject $entry -Name 'id')
                    if ([string]::IsNullOrWhiteSpace($entryId)) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_entry_id' -Message 'Audit closure entry id must be non-empty.' -Path ("{0}.id" -f $entryPath)
                    }
                    elseif (-not $seenIds.Add($entryId)) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_duplicate_entry_id' -Message ("Audit closure entry id '{0}' is duplicated." -f $entryId) -Path ("{0}.id" -f $entryPath)
                    }

                    $entryStatus = [string](Get-McAuditPropertyValue -InputObject $entry -Name 'status')
                    if ($entryStatus -notin @('verified', 'changed', 'partial', 'unresolved', 'candidate-only', 'unknown')) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_entry_status' -Message 'Audit closure entry status is not recognized.' -Path ("{0}.status" -f $entryPath)
                    }

                    if (Test-McAuditPropertyPresent -InputObject $entry -Name 'evidence') {
                        Test-McAuditSequenceProperty -Value (Get-McAuditPropertyValue -InputObject $entry -Name 'evidence') -Errors $errors -Path ("{0}.evidence" -f $entryPath)
                    }
                    if (Test-McAuditPropertyPresent -InputObject $entry -Name 'facts') {
                        Test-McAuditSequenceProperty -Value (Get-McAuditPropertyValue -InputObject $entry -Name 'facts') -Errors $errors -Path ("{0}.facts" -f $entryPath)
                    }
                    $entryIndex++
                }
            }
        }

        $documentSource = Get-McAuditPropertyValue -InputObject $InputObject -Name 'source'
        if ($null -ne $documentSource -and [string]::IsNullOrWhiteSpace([string]$documentSource)) {
            [void]$warnings.Add([pscustomobject][ordered]@{
                    severity = 'warning'
                    code = 'audit_closure_blank_source'
                    message = 'Audit closure source is present but empty.'
                    path = '$.source'
                })
        }
    }

    if ($null -ne $InputObject -and (Test-McMapping -InputObject $InputObject)) {
        $summary = Get-McAuditPropertyValue -InputObject $InputObject -Name 'summary'
        if (Test-McMapping -InputObject $summary) {
            $accepted = @((Get-McAuditPropertyValue -InputObject $summary -Name 'accepted_unknowns') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $open = @((Get-McAuditPropertyValue -InputObject $summary -Name 'open_unknowns') | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $overlap = @($accepted | Where-Object { $_ -in $open })
            foreach ($item in $overlap) {
                Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_unknown_classification_conflict' -Message ("Unknown is classified as both accepted and open: {0}" -f $item) -Path '$.summary'
            }

            $declaredState = [string](Get-McAuditPropertyValue -InputObject $summary -Name 'state')
            if ($declaredState -eq 'verified' -and $projection.state -ne 'verified') {
                Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'audit_closure_state_mismatch' -Message 'summary.state is verified but the derived closure projection is still partial.' -Path '$.summary.state'
            }
        }
    }

    return [pscustomobject][ordered]@{
        ok = ($errors.Count -eq 0)
        read_only = $true
        source = $Source
        entry_count = $entryCount
        run_id_count = $runIdCount
        closure = $projection
        errors = @($errors.ToArray())
        warnings = @($warnings.ToArray())
    }
}

function Get-McAuditClosureReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $relativePath = '.local/audit-closure.json'
    $path = Join-Path $RepoRoot '.local\audit-closure.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $projection = ConvertTo-McAuditClosureProjection -Source $relativePath -UnavailableReason 'missing'
        return [pscustomobject][ordered]@{
            ok = $false
            read_only = $true
            source = $relativePath
            entry_count = 0
            run_id_count = 0
            closure = $projection
            errors = @([pscustomobject][ordered]@{
                    severity = 'error'
                    code = 'audit_closure_missing'
                    message = 'Ignored audit closure file does not exist.'
                    path = $relativePath
                })
            warnings = @()
        }
    }

    try {
        $closure = Read-McJson -Path $path
    }
    catch {
        return [pscustomobject][ordered]@{
            ok = $false
            read_only = $true
            source = $relativePath
            entry_count = 0
            run_id_count = 0
            closure = (ConvertTo-McAuditClosureProjection -Source $relativePath -UnavailableReason 'invalid')
            errors = @([pscustomobject][ordered]@{
                    severity = 'error'
                    code = 'audit_closure_invalid_json'
                    message = 'Ignored audit closure file could not be parsed as JSON.'
                    path = $relativePath
                })
            warnings = @()
        }
    }

    return Test-McAuditClosureDocument -InputObject $closure -Source $relativePath
}
