Set-StrictMode -Version Latest

function Test-McReviewBoolean {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Errors,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($null -eq $Value -or $Value -isnot [bool]) {
        Add-McAuditReviewFinding -Findings $Errors -Severity error -Code 'semantic_review_boolean_type' -Message $Message -Path $Path
        return $false
    }
    return $true
}

function Test-McReviewRequiredString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Errors,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        Add-McAuditReviewFinding -Findings $Errors -Severity error -Code 'semantic_review_required_string' -Message $Message -Path $Path
        return $false
    }
    return $true
}

function Test-McReviewEvidence {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Errors,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($null -eq $Value -or (-not (Test-McMapping -InputObject $Value) -and -not (Test-McSequence -InputObject $Value))) {
        Add-McAuditReviewFinding -Findings $Errors -Severity error -Code 'semantic_review_evidence_type' -Message 'Review evidence must be a JSON object or sequence.' -Path $Path
    }
}

function Test-McG2SemanticReviewDocument {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [string]$Source = 'unknown'
    )

    $errors = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[object]]::new()
    $projectCount = 0
    $semanticCount = 0
    $unresolvedCount = 0
    $confirmationCount = 0
    $canonicalWrite = $null

    if (-not (Test-McMapping -InputObject $InputObject)) {
        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_root_type' -Message 'G2 semantic review root must be a JSON object.' -Path '$'
    }
    else {
        $schemaVersion = Get-McAuditPropertyValue -InputObject $InputObject -Name 'schema_version'
        $parsedSchemaVersion = 0
        if (-not [int]::TryParse([string]$schemaVersion, [ref]$parsedSchemaVersion) -or $parsedSchemaVersion -ne 1) {
            Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_schema_version' -Message 'G2 semantic review schema_version must be 1.' -Path '$.schema_version'
        }

        $kind = Get-McAuditPropertyValue -InputObject $InputObject -Name 'kind'
        if ([string]$kind -cne 'g2-semantic-review-draft') {
            Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_kind' -Message 'G2 semantic review kind must be g2-semantic-review-draft.' -Path '$.kind'
        }

        [void](Test-McReviewRequiredString -Value (Get-McAuditPropertyValue -InputObject $InputObject -Name 'generated_at') -Errors $errors -Path '$.generated_at' -Message 'G2 semantic review generated_at must be non-empty.')
        [void](Test-McReviewRequiredString -Value (Get-McAuditPropertyValue -InputObject $InputObject -Name 'source') -Errors $errors -Path '$.source' -Message 'G2 semantic review source must be non-empty.')

        $canonicalWrite = Get-McAuditPropertyValue -InputObject $InputObject -Name 'canonical_write'
        if (Test-McReviewBoolean -Value $canonicalWrite -Errors $errors -Path '$.canonical_write' -Message 'G2 semantic review canonical_write must be a Boolean.') {
            if ($canonicalWrite) {
                Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_canonical_write' -Message 'G2 semantic review must never authorize canonical writes.' -Path '$.canonical_write'
            }
        }

        foreach ($field in @('project_suggestions', 'semantic_suggestions', 'unresolved_checks')) {
            if (-not (Test-McAuditPropertyPresent -InputObject $InputObject -Name $field)) {
                Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_missing_sequence' -Message ("G2 semantic review must contain '{0}'." -f $field) -Path ("$.{0}" -f $field)
                continue
            }
            Test-McAuditSequenceProperty -Value (Get-McAuditPropertyValue -InputObject $InputObject -Name $field) -Errors $errors -Path ("$.{0}" -f $field)
        }

        $projectSuggestions = Get-McAuditPropertyValue -InputObject $InputObject -Name 'project_suggestions'
        if ($null -ne $projectSuggestions -and (Test-McSequence -InputObject $projectSuggestions)) {
            $projectItems = @($projectSuggestions)
            $projectCount = $projectItems.Count
            $seenProjectIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $index = 0
            foreach ($item in $projectItems) {
                $path = "$.project_suggestions[{0}]" -f $index
                if (-not (Test-McMapping -InputObject $item)) {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_project_item_type' -Message 'Project suggestions must contain JSON objects.' -Path $path
                    $index++
                    continue
                }
                $id = Get-McAuditPropertyValue -InputObject $item -Name 'id'
                if (Test-McReviewRequiredString -Value $id -Errors $errors -Path ("{0}.id" -f $path) -Message 'Project suggestion id must be non-empty.') {
                    if (-not $seenProjectIds.Add([string]$id)) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_duplicate_project_id' -Message ("Project suggestion id '{0}' is duplicated." -f $id) -Path ("{0}.id" -f $path)
                    }
                }
                [void](Test-McReviewRequiredString -Value (Get-McAuditPropertyValue -InputObject $item -Name 'current_status') -Errors $errors -Path ("{0}.current_status" -f $path) -Message 'Project suggestion current_status must be non-empty.')
                [void](Test-McReviewRequiredString -Value (Get-McAuditPropertyValue -InputObject $item -Name 'review_bucket') -Errors $errors -Path ("{0}.review_bucket" -f $path) -Message 'Project suggestion review_bucket must be non-empty.')
                $confidence = [string](Get-McAuditPropertyValue -InputObject $item -Name 'confidence')
                if ($confidence -notin @('low', 'medium', 'high')) {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_confidence' -Message 'Project suggestion confidence must be low, medium, or high.' -Path ("{0}.confidence" -f $path)
                }
                if (Test-McAuditPropertyPresent -InputObject $item -Name 'evidence') {
                    Test-McReviewEvidence -Value (Get-McAuditPropertyValue -InputObject $item -Name 'evidence') -Errors $errors -Path ("{0}.evidence" -f $path)
                }
                else {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_missing_evidence' -Message 'Project suggestion must retain evidence references.' -Path ("{0}.evidence" -f $path)
                }
                $requiresConfirmation = Get-McAuditPropertyValue -InputObject $item -Name 'requires_confirmation'
                if (Test-McReviewBoolean -Value $requiresConfirmation -Errors $errors -Path ("{0}.requires_confirmation" -f $path) -Message 'Project suggestions must declare requires_confirmation as a Boolean.') {
                    if (-not $requiresConfirmation) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_confirmation_bypass' -Message 'Project suggestions must remain confirmation-gated.' -Path ("{0}.requires_confirmation" -f $path)
                    }
                    else {
                        $confirmationCount++
                    }
                }
                $index++
            }
        }

        $semanticSuggestions = Get-McAuditPropertyValue -InputObject $InputObject -Name 'semantic_suggestions'
        if ($null -ne $semanticSuggestions -and (Test-McSequence -InputObject $semanticSuggestions)) {
            $semanticItems = @($semanticSuggestions)
            $semanticCount = $semanticItems.Count
            $seenTopics = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $index = 0
            foreach ($item in $semanticItems) {
                $path = "$.semantic_suggestions[{0}]" -f $index
                if (-not (Test-McMapping -InputObject $item)) {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_semantic_item_type' -Message 'Semantic suggestions must contain JSON objects.' -Path $path
                    $index++
                    continue
                }
                $topic = Get-McAuditPropertyValue -InputObject $item -Name 'topic'
                if (Test-McReviewRequiredString -Value $topic -Errors $errors -Path ("{0}.topic" -f $path) -Message 'Semantic suggestion topic must be non-empty.') {
                    if (-not $seenTopics.Add([string]$topic)) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_duplicate_topic' -Message ("Semantic suggestion topic '{0}' is duplicated." -f $topic) -Path ("{0}.topic" -f $path)
                    }
                }
                [void](Test-McReviewRequiredString -Value (Get-McAuditPropertyValue -InputObject $item -Name 'suggestion') -Errors $errors -Path ("{0}.suggestion" -f $path) -Message 'Semantic suggestion text must be non-empty.')
                if (Test-McAuditPropertyPresent -InputObject $item -Name 'evidence') {
                    Test-McReviewEvidence -Value (Get-McAuditPropertyValue -InputObject $item -Name 'evidence') -Errors $errors -Path ("{0}.evidence" -f $path)
                }
                else {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_missing_evidence' -Message 'Semantic suggestion must retain evidence references.' -Path ("{0}.evidence" -f $path)
                }
                $requiresConfirmation = Get-McAuditPropertyValue -InputObject $item -Name 'requires_confirmation'
                if (Test-McReviewBoolean -Value $requiresConfirmation -Errors $errors -Path ("{0}.requires_confirmation" -f $path) -Message 'Semantic suggestions must declare requires_confirmation as a Boolean.') {
                    if (-not $requiresConfirmation) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_confirmation_bypass' -Message 'Semantic suggestions must remain confirmation-gated.' -Path ("{0}.requires_confirmation" -f $path)
                    }
                    else {
                        $confirmationCount++
                    }
                }
                $index++
            }
        }

        $unresolvedChecks = Get-McAuditPropertyValue -InputObject $InputObject -Name 'unresolved_checks'
        if ($null -ne $unresolvedChecks -and (Test-McSequence -InputObject $unresolvedChecks)) {
            $unresolvedItems = @($unresolvedChecks)
            $unresolvedCount = $unresolvedItems.Count
            $seenCheckIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            $index = 0
            foreach ($item in $unresolvedItems) {
                $path = "$.unresolved_checks[{0}]" -f $index
                if (-not (Test-McMapping -InputObject $item)) {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_unresolved_item_type' -Message 'Unresolved checks must contain JSON objects.' -Path $path
                    $index++
                    continue
                }
                $id = Get-McAuditPropertyValue -InputObject $item -Name 'id'
                if (Test-McReviewRequiredString -Value $id -Errors $errors -Path ("{0}.id" -f $path) -Message 'Unresolved check id must be non-empty.') {
                    if (-not $seenCheckIds.Add([string]$id)) {
                        Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_duplicate_check_id' -Message ("Unresolved check id '{0}' is duplicated." -f $id) -Path ("{0}.id" -f $path)
                    }
                }
                $state = [string](Get-McAuditPropertyValue -InputObject $item -Name 'state')
                if ($state -notin @('verified', 'changed', 'verified-absent', 'unresolved', 'unverified', 'candidate-only')) {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_check_state' -Message 'Unresolved check state is not recognized.' -Path ("{0}.state" -f $path)
                }
                if (Test-McAuditPropertyPresent -InputObject $item -Name 'evidence') {
                    Test-McReviewEvidence -Value (Get-McAuditPropertyValue -InputObject $item -Name 'evidence') -Errors $errors -Path ("{0}.evidence" -f $path)
                }
                else {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_missing_evidence' -Message 'Unresolved check must retain evidence references.' -Path ("{0}.evidence" -f $path)
                }
                $absenceClaimPath = "{0}.absence_claim" -f $path
                if (Test-McAuditPropertyPresent -InputObject $item -Name 'absence_claim') {
                    $absenceClaim = Get-McAuditPropertyValue -InputObject $item -Name 'absence_claim'
                    if (Test-McReviewBoolean -Value $absenceClaim -Errors $errors -Path $absenceClaimPath -Message 'Unresolved checks must declare absence_claim as a Boolean.') {
                        if ($absenceClaim -and $state -ne 'verified-absent') {
                            Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_unsafe_absence_claim' -Message 'Only a verified-absent check may carry absence_claim=true.' -Path $absenceClaimPath
                        }
                    }
                }
                elseif ($state -eq 'verified-absent') {
                    Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_missing_absence_claim' -Message 'A verified-absent check must explicitly declare absence_claim=true.' -Path $absenceClaimPath
                }
                else {
                    [void]$warnings.Add([pscustomobject][ordered]@{
                            severity = 'warning'
                            code = 'semantic_review_implicit_nonabsence'
                            message = 'Unresolved, unverified, or candidate-only checks without absence_claim are treated as not-absent and remain confirmation-gated.'
                            path = $absenceClaimPath
                        })
                }
                if (Test-McAuditPropertyPresent -InputObject $item -Name 'promotion_eligible') {
                    $promotionEligible = Get-McAuditPropertyValue -InputObject $item -Name 'promotion_eligible'
                    if (Test-McReviewBoolean -Value $promotionEligible -Errors $errors -Path ("{0}.promotion_eligible" -f $path) -Message 'Promotion eligibility must be a Boolean.') {
                        if ($state -eq 'candidate-only' -and $promotionEligible) {
                            Add-McAuditReviewFinding -Findings $errors -Severity error -Code 'semantic_review_candidate_promotion' -Message 'Candidate-only checks cannot be marked promotion-eligible.' -Path ("{0}.promotion_eligible" -f $path)
                        }
                    }
                }
                if ($state -in @('unresolved', 'unverified', 'candidate-only')) {
                    $confirmationCount++
                }
                $index++
            }
        }

        $documentSource = Get-McAuditPropertyValue -InputObject $InputObject -Name 'source'
        if ($null -ne $documentSource -and [string]::IsNullOrWhiteSpace([string]$documentSource)) {
            [void]$warnings.Add([pscustomobject][ordered]@{
                    severity = 'warning'
                    code = 'semantic_review_blank_source'
                    message = 'G2 semantic review source is present but empty.'
                    path = '$.source'
                })
        }
    }

    return [pscustomobject][ordered]@{
        ok = ($errors.Count -eq 0)
        read_only = $true
        source = $Source
        canonical_write = $canonicalWrite
        requires_confirmation = ($confirmationCount -gt 0)
        confirmation_count = $confirmationCount
        project_suggestion_count = $projectCount
        semantic_suggestion_count = $semanticCount
        unresolved_check_count = $unresolvedCount
        errors = @($errors.ToArray())
        warnings = @($warnings.ToArray())
    }
}

function Get-McSemanticReview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $relativePath = '.local/g2-semantic-review.json'
    $path = Join-Path $RepoRoot '.local\g2-semantic-review.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject][ordered]@{
            ok = $false
            read_only = $true
            source = $relativePath
            canonical_write = $null
            requires_confirmation = $true
            confirmation_count = 0
            project_suggestion_count = 0
            semantic_suggestion_count = 0
            unresolved_check_count = 0
            errors = @([pscustomobject][ordered]@{
                    severity = 'error'
                    code = 'semantic_review_missing'
                    message = 'Ignored G2 semantic review draft does not exist.'
                    path = $relativePath
                })
            warnings = @()
        }
    }

    try {
        $review = Read-McJson -Path $path
    }
    catch {
        return [pscustomobject][ordered]@{
            ok = $false
            read_only = $true
            source = $relativePath
            canonical_write = $null
            requires_confirmation = $true
            confirmation_count = 0
            project_suggestion_count = 0
            semantic_suggestion_count = 0
            unresolved_check_count = 0
            errors = @([pscustomobject][ordered]@{
                    severity = 'error'
                    code = 'semantic_review_invalid_json'
                    message = 'Ignored G2 semantic review draft could not be parsed as JSON.'
                    path = $relativePath
                })
            warnings = @()
        }
    }

    return Test-McG2SemanticReviewDocument -InputObject $review -Source $relativePath
}
