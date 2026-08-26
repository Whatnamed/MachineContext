Set-StrictMode -Version Latest

$script:McCurationStatuses = @('active', 'inactive', 'legacy', 'testing', 'broken', 'unknown')
$script:McCurationRoles = @('primary', 'secondary', 'project-only', 'optional')
$script:McCurationRootKinds = @('project-root', 'workspace-root', 'developer-root', 'tool-root', 'sdk-root', 'cache-root', 'vendor-root', 'unknown-root')

function Add-McCurationFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [string]$Path
    )

    [void]$Findings.Add([pscustomobject][ordered]@{
            severity = 'error'
            code     = $Code
            message  = $Message
            path     = $Path
        })
}

function Test-McCurationPropertyPresent {
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

function Test-McCurationRequiredString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        Add-McCurationFinding -Findings $Findings -Code $Code -Message $Message -Path $Path
        return $false
    }
    return $true
}

function Test-McCurationAllowedProperties {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string[]]$Allowed,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if ($null -eq $InputObject -or -not (Test-McMapping -InputObject $InputObject)) {
        Add-McCurationFinding -Findings $Findings -Code 'curation_mapping_type' -Message 'Curation object must be a JSON object.' -Path $Path
        return $false
    }

    $allowedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($name in $Allowed) { [void]$allowedSet.Add($name) }
    foreach ($entry in @(Get-McPropertyEntries -InputObject $InputObject)) {
        $name = [string]$entry.name
        if (-not $allowedSet.Contains($name)) {
            Add-McCurationFinding -Findings $Findings -Code 'curation_forbidden_property' -Message ("Property '{0}' is not allowed in a confirmation manifest." -f $name) -Path ("{0}.{1}" -f $Path, $name)
        }
    }
    return $true
}

function Test-McCurationNoObserved {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [object]$Findings,

        [string]$Path = '$'
    )

    if ($null -eq $InputObject) { return }
    if (Test-McMapping -InputObject $InputObject) {
        foreach ($entry in @(Get-McPropertyEntries -InputObject $InputObject)) {
            $name = [string]$entry.name
            $childPath = "{0}.{1}" -f $Path, $name
            if ($name -eq 'observed') {
                Add-McCurationFinding -Findings $Findings -Code 'curation_observed_write' -Message 'Confirmation manifests may never contain observed updates.' -Path $childPath
                continue
            }
            Test-McCurationNoObserved -InputObject $entry.value -Findings $Findings -Path $childPath
        }
        return
    }
    if (Test-McSequence -InputObject $InputObject) {
        $index = 0
        foreach ($item in @($InputObject)) {
            Test-McCurationNoObserved -InputObject $item -Findings $Findings -Path ("{0}[{1}]" -f $Path, $index)
            $index++
        }
    }
}

function Test-McCurationStringSequence {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Message,

        [switch]$AllowSingleString,

        [switch]$AllowNullAsEmpty
    )

    if ($null -eq $Value -and $AllowNullAsEmpty) {
        return $true
    }
    if ($AllowSingleString -and $Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace([string]$Value)) {
            Add-McCurationFinding -Findings $Findings -Code 'curation_string_sequence_item' -Message 'Curation string sequences may contain only non-empty strings.' -Path $Path
            return $false
        }
        return $true
    }
    if (-not (Test-McSequence -InputObject $Value)) {
        Add-McCurationFinding -Findings $Findings -Code 'curation_sequence_type' -Message $Message -Path $Path
        return $false
    }
    $index = 0
    foreach ($item in @($Value)) {
        if ($null -eq $item -or $item -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$item)) {
            Add-McCurationFinding -Findings $Findings -Code 'curation_string_sequence_item' -Message 'Curation string sequences may contain only non-empty strings.' -Path ("{0}[{1}]" -f $Path, $index)
        }
        $index++
    }
    return $true
}

function Test-McCurationUpdateSequence {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Message
    )

    # ConvertFrom-Json in PowerShell exposes a one-item JSON array as its item
    # rather than an IList. Treat mappings as a one-item sequence here, while
    # retaining strict element validation below.
    if ($null -eq $Value) { return @() }
    if (Test-McSequence -InputObject $Value) { return @($Value) }
    if (Test-McMapping -InputObject $Value) { return @($Value) }
    Add-McCurationFinding -Findings $Findings -Code 'curation_updates_type' -Message $Message -Path $Path
    return $null
}

function Test-McCurationEntityPatch {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Patch,

        [Parameter(Mandatory)]
        [string[]]$Allowed,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McCurationAllowedProperties -InputObject $Patch -Allowed $Allowed -Findings $Findings -Path $Path)) {
        return $false
    }
    $status = Get-McObjectPropertyOrNull -InputObject $Patch -Name 'status'
    if ((Test-McCurationPropertyPresent -InputObject $Patch -Name 'status') -and ([string]$status -notin $script:McCurationStatuses)) {
        Add-McCurationFinding -Findings $Findings -Code 'curation_status_value' -Message ("Status must be one of: {0}." -f ($script:McCurationStatuses -join ', ')) -Path ("{0}.status" -f $Path)
    }
    $role = Get-McObjectPropertyOrNull -InputObject $Patch -Name 'role'
    if ((Test-McCurationPropertyPresent -InputObject $Patch -Name 'role') -and ([string]$role -notin $script:McCurationRoles)) {
        Add-McCurationFinding -Findings $Findings -Code 'curation_role_value' -Message ("Role must be one of: {0}." -f ($script:McCurationRoles -join ', ')) -Path ("{0}.role" -f $Path)
    }
    foreach ($name in @('purpose', 'notes')) {
        if (Test-McCurationPropertyPresent -InputObject $Patch -Name $name) {
            $value = Get-McObjectPropertyOrNull -InputObject $Patch -Name $name
            if ($null -ne $value -and $value -isnot [string]) {
                Add-McCurationFinding -Findings $Findings -Code 'curation_text_type' -Message ("Curated {0} must be a string or null." -f $name) -Path ("{0}.{1}" -f $Path, $name)
            }
        }
    }
    if (Test-McCurationPropertyPresent -InputObject $Patch -Name 'constraints') {
        [void](Test-McCurationStringSequence -Value (Get-McObjectPropertyOrNull -InputObject $Patch -Name 'constraints') -Findings $Findings -Path ("{0}.constraints" -f $Path) -Message 'Curated constraints must be a sequence of strings.' -AllowSingleString -AllowNullAsEmpty)
    }
    return $true
}

function Test-McCurationConventionsUpdate {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Update,

        [Parameter(Mandatory)]
        [object]$Findings,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-McCurationAllowedProperties -InputObject $Update -Allowed @('evidence_refs', 'meta', 'directories', 'installation', 'updates', 'principles') -Findings $Findings -Path $Path)) {
        return $false
    }
    [void](Test-McCurationStringSequence -Value (Get-McObjectPropertyOrNull -InputObject $Update -Name 'evidence_refs') -Findings $Findings -Path ("{0}.evidence_refs" -f $Path) -Message 'Conventions evidence_refs must be a non-empty sequence of strings.' -AllowSingleString)

    $meta = Get-McObjectPropertyOrNull -InputObject $Update -Name 'meta'
    if (-not (Test-McCurationPropertyPresent -InputObject $Update -Name 'meta')) {
        Add-McCurationFinding -Findings $Findings -Code 'curation_conventions_meta' -Message 'A conventions confirmation must include meta.state=confirmed.' -Path ("{0}.meta" -f $Path)
    }
    else {
        if (Test-McCurationAllowedProperties -InputObject $meta -Allowed @('state', 'note') -Findings $Findings -Path ("{0}.meta" -f $Path)) {
            $state = Get-McObjectPropertyOrNull -InputObject $meta -Name 'state'
            if ([string]$state -cne 'confirmed') {
                Add-McCurationFinding -Findings $Findings -Code 'curation_conventions_state' -Message 'A conventions confirmation must set meta.state to confirmed.' -Path ("{0}.meta.state" -f $Path)
            }
        }
    }

    $directories = Get-McObjectPropertyOrNull -InputObject $Update -Name 'directories'
    if (Test-McCurationPropertyPresent -InputObject $Update -Name 'directories') {
        if (Test-McCurationAllowedProperties -InputObject $directories -Allowed @('known_roots') -Findings $Findings -Path ("{0}.directories" -f $Path)) {
            $roots = Get-McObjectPropertyOrNull -InputObject $directories -Name 'known_roots'
            if ($null -eq $roots) {
                $roots = @()
            }
            elseif ((Test-McMapping -InputObject $roots) -or ($roots -is [string])) {
                $roots = @($roots)
            }
            elseif (-not (Test-McSequence -InputObject $roots)) {
                Add-McCurationFinding -Findings $Findings -Code 'curation_known_roots_type' -Message 'Conventions known_roots must be a sequence.' -Path ("{0}.directories.known_roots" -f $Path)
            }
            if (($null -ne $roots) -and ((Test-McSequence -InputObject $roots) -or ($roots.Count -gt 0))) {
                $index = 0
                foreach ($root in @($roots)) {
                    $rootPath = "{0}.directories.known_roots[{1}]" -f $Path, $index
                    if ($root -is [string]) {
                        if ([string]::IsNullOrWhiteSpace([string]$root)) { Add-McCurationFinding -Findings $Findings -Code 'curation_known_root_path' -Message 'Known root paths must be non-empty.' -Path $rootPath }
                    }
                    elseif (Test-McMapping -InputObject $root) {
                        if (Test-McCurationAllowedProperties -InputObject $root -Allowed @('path', 'kind', 'notes') -Findings $Findings -Path $rootPath) {
                            [void](Test-McCurationRequiredString -Value (Get-McObjectPropertyOrNull -InputObject $root -Name 'path') -Findings $Findings -Path ("{0}.path" -f $rootPath) -Code 'curation_known_root_path' -Message 'Known root path must be non-empty.')
                            $kind = [string](Get-McObjectPropertyOrNull -InputObject $root -Name 'kind')
                            if (-not [string]::IsNullOrWhiteSpace($kind) -and $kind -notin $script:McCurationRootKinds) {
                                Add-McCurationFinding -Findings $Findings -Code 'curation_known_root_kind' -Message ("Known root kind must be one of: {0}." -f ($script:McCurationRootKinds -join ', ')) -Path ("{0}.kind" -f $rootPath)
                            }
                        }
                    }
                    else {
                        Add-McCurationFinding -Findings $Findings -Code 'curation_known_root_item' -Message 'Known roots must be strings or objects.' -Path $rootPath
                    }
                    $index++
                }
            }
        }
    }

    foreach ($section in @('installation', 'updates')) {
        if (Test-McCurationPropertyPresent -InputObject $Update -Name $section) {
            $value = Get-McObjectPropertyOrNull -InputObject $Update -Name $section
            if (-not (Test-McMapping -InputObject $value)) {
                Add-McCurationFinding -Findings $Findings -Code 'curation_conventions_section_type' -Message ("Conventions {0} must be an object." -f $section) -Path ("{0}.{1}" -f $Path, $section)
            }
            else {
                $allowed = if ($section -eq 'installation') { @('prefer_existing_directory_conventions', 'record_install_method', 'record_path_and_scope', 'record_update_method') } else { @('prefer_original_package_manager_or_vendor_updater', 'verify_version_after_update') }
                [void](Test-McCurationAllowedProperties -InputObject $value -Allowed $allowed -Findings $Findings -Path ("{0}.{1}" -f $Path, $section))
                foreach ($entry in @(Get-McPropertyEntries -InputObject $value)) {
                    if ($entry.value -isnot [bool]) {
                        Add-McCurationFinding -Findings $Findings -Code 'curation_conventions_boolean' -Message 'Conventions installation/update values must be Boolean.' -Path ("{0}.{1}.{2}" -f $Path, $section, $entry.name)
                    }
                }
            }
        }
    }
    if (Test-McCurationPropertyPresent -InputObject $Update -Name 'principles') {
        [void](Test-McCurationStringSequence -Value (Get-McObjectPropertyOrNull -InputObject $Update -Name 'principles') -Findings $Findings -Path ("{0}.principles" -f $Path) -Message 'Conventions principles must be a sequence of strings.' -AllowSingleString -AllowNullAsEmpty)
    }
    return $true
}

function Test-McG2CurationConfirmationDocument {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $errors = [System.Collections.Generic.List[object]]::new()
    if (-not (Test-McMapping -InputObject $InputObject)) {
        Add-McCurationFinding -Findings $errors -Code 'curation_root_type' -Message 'Curation confirmation root must be a JSON object.' -Path '$'
    }
    else {
        [void](Test-McCurationAllowedProperties -InputObject $InputObject -Allowed @('schema_version', 'kind', 'confirmed', 'confirmed_at', 'source_review', 'project_updates', 'software_updates', 'conventions_update') -Findings $errors -Path '$')
        $schemaVersion = 0
        if (-not [int]::TryParse([string](Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'schema_version'), [ref]$schemaVersion) -or $schemaVersion -ne 1) {
            Add-McCurationFinding -Findings $errors -Code 'curation_schema_version' -Message 'Curation confirmation schema_version must be 1.' -Path '$.schema_version'
        }
        if ([string](Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'kind') -cne 'g2-curation-confirmation') {
            Add-McCurationFinding -Findings $errors -Code 'curation_kind' -Message 'Curation confirmation kind must be g2-curation-confirmation.' -Path '$.kind'
        }
        $confirmed = Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'confirmed'
        if ($confirmed -isnot [bool] -or -not $confirmed) {
            Add-McCurationFinding -Findings $errors -Code 'curation_not_confirmed' -Message 'Curation confirmation must explicitly set confirmed=true.' -Path '$.confirmed'
        }
        [void](Test-McCurationRequiredString -Value (Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'confirmed_at') -Findings $errors -Path '$.confirmed_at' -Code 'curation_confirmed_at' -Message 'confirmed_at must be non-empty.')
        $sourceReview = [string](Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'source_review')
        if ($sourceReview -cne '.local/g2-semantic-review.json') {
            Add-McCurationFinding -Findings $errors -Code 'curation_source_review' -Message 'source_review must point to .local/g2-semantic-review.json.' -Path '$.source_review'
        }
        elseif (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.local\g2-semantic-review.json') -PathType Leaf)) {
            Add-McCurationFinding -Findings $errors -Code 'curation_source_review_missing' -Message 'The referenced G2 semantic review draft does not exist.' -Path '$.source_review'
        }

        foreach ($field in @('project_updates', 'software_updates')) {
            $value = Get-McObjectPropertyOrNull -InputObject $InputObject -Name $field
            $items = Test-McCurationUpdateSequence -Value $value -Findings $errors -Path ("$.{0}" -f $field) -Message ("{0} must be a sequence." -f $field)
            if ($null -eq $items) {
                continue
            }
            $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            $index = 0
            foreach ($update in @($items)) {
                $path = "$.{0}[{1}]" -f $field, $index
                if (-not (Test-McCurationAllowedProperties -InputObject $update -Allowed @('id', 'curated', 'evidence_refs') -Findings $errors -Path $path)) {
                    $index++
                    continue
                }
                $id = [string](Get-McObjectPropertyOrNull -InputObject $update -Name 'id')
                if (Test-McCurationRequiredString -Value $id -Findings $errors -Path ("{0}.id" -f $path) -Code 'curation_update_id' -Message 'Each curation update needs a stable id.') {
                    if (-not $seen.Add($id)) { Add-McCurationFinding -Findings $errors -Code 'curation_duplicate_id' -Message ("Curation id '{0}' is duplicated." -f $id) -Path ("{0}.id" -f $path) }
                }
                [void](Test-McCurationStringSequence -Value (Get-McObjectPropertyOrNull -InputObject $update -Name 'evidence_refs') -Findings $errors -Path ("{0}.evidence_refs" -f $path) -Message 'Each curation update needs non-empty evidence_refs.' -AllowSingleString)
                $allowedPatch = if ($field -eq 'project_updates') { @('status', 'purpose', 'constraints') } else { @('status', 'role', 'purpose', 'constraints', 'notes') }
                [void](Test-McCurationEntityPatch -Patch (Get-McObjectPropertyOrNull -InputObject $update -Name 'curated') -Allowed $allowedPatch -Findings $errors -Path ("{0}.curated" -f $path))
                $index++
            }
        }

        if (Test-McCurationPropertyPresent -InputObject $InputObject -Name 'conventions_update') {
            [void](Test-McCurationConventionsUpdate -Update (Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'conventions_update') -Findings $errors -Path '$.conventions_update')
        }

        $projectCount = @((Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'project_updates')).Count
        $softwareCount = @((Get-McObjectPropertyOrNull -InputObject $InputObject -Name 'software_updates')).Count
        $conventionsCount = if (Test-McCurationPropertyPresent -InputObject $InputObject -Name 'conventions_update') { 1 } else { 0 }
        if (($projectCount + $softwareCount + $conventionsCount) -eq 0) {
            Add-McCurationFinding -Findings $errors -Code 'curation_empty' -Message 'Confirmation must contain at least one explicit curated update.' -Path '$'
        }
        Test-McCurationNoObserved -InputObject $InputObject -Findings $errors
    }

    return [pscustomobject][ordered]@{
        ok = ($errors.Count -eq 0)
        errors = @($errors.ToArray())
    }
}

function Merge-McCurationObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Existing,

        [Parameter(Mandatory)]
        [object]$Patch
    )

    $result = if (Test-McMapping -InputObject $Existing) { Copy-McJsonObject -InputObject $Existing } else { [pscustomobject][ordered]@{} }
    foreach ($entry in @(Get-McPropertyEntries -InputObject $Patch)) {
        Set-McObjectProperty -InputObject $result -Name ([string]$entry.name) -Value (Copy-McJsonObject -InputObject $entry.value)
    }
    return $result
}

function Get-McCurationCanonicalTargets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $targets = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $contextRoot = Join-Path $RepoRoot 'context'
    $projectRoot = Join-Path $contextRoot 'projects'
    foreach ($file in @(Get-ChildItem -LiteralPath $projectRoot -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('_template.json', 'index.json') })) {
        $record = Read-McJson -Path $file.FullName
        $id = [string](Get-McObjectPropertyOrNull -InputObject $record -Name 'id')
        if (-not [string]::IsNullOrWhiteSpace($id)) {
            $key = 'project|{0}' -f $id
            if ($targets.ContainsKey($key)) { throw "Duplicate canonical project id: $id" }
            $targets[$key] = [pscustomobject][ordered]@{ id = $id; kind = 'project'; path = $file.FullName; relative_path = 'context/projects/{0}' -f $file.Name; index = $null }
        }
    }

    $softwareRoot = Join-Path $contextRoot 'software'
    foreach ($file in @(Get-ChildItem -LiteralPath $softwareRoot -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '_template.json' })) {
        $module = Read-McJson -Path $file.FullName
        $entities = @((Get-McObjectPropertyOrNull -InputObject $module -Name 'software'))
        for ($index = 0; $index -lt $entities.Count; $index++) {
            $id = [string](Get-McObjectPropertyOrNull -InputObject $entities[$index] -Name 'id')
            if ([string]::IsNullOrWhiteSpace($id)) { continue }
            $key = 'software|{0}' -f $id
            if ($targets.ContainsKey($key)) { throw "Duplicate canonical software id: $id" }
            $targets[$key] = [pscustomobject][ordered]@{ id = $id; kind = 'software'; path = $file.FullName; relative_path = 'context/software/{0}' -f $file.Name; index = $index }
        }
    }
    return $targets
}

function New-McCurationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [string]$ConfirmationPath
    )

    $document = Read-McJson -Path $ConfirmationPath
    $documentReview = Test-McG2CurationConfirmationDocument -InputObject $document -RepoRoot $RepoRoot
    if (-not $documentReview.ok) {
        return [pscustomobject][ordered]@{ ok = $false; errors = @($documentReview.errors); changes = @(); proposed_documents = @{}; confirmation_path = $ConfirmationPath }
    }

    $targets = Get-McCurationCanonicalTargets -RepoRoot $RepoRoot
    $documents = @{}
    $errors = [System.Collections.Generic.List[object]]::new()
    $addDocument = {
        param([string]$Path)
        if (-not $documents.ContainsKey($Path)) { $documents[$Path] = Copy-McJsonObject -InputObject (Read-McJson -Path $Path) }
        return $documents[$Path]
    }

    foreach ($field in @('project_updates', 'software_updates')) {
        $updatesValue = Get-McObjectPropertyOrNull -InputObject $document -Name $field
        $updates = if ($null -eq $updatesValue) { @() } else { @($updatesValue) }
        foreach ($update in $updates) {
            $id = [string](Get-McObjectPropertyOrNull -InputObject $update -Name 'id')
            $kind = if ($field -eq 'project_updates') { 'project' } else { 'software' }
            $key = '{0}|{1}' -f $kind, $id
            if (-not $targets.ContainsKey($key)) {
                Add-McCurationFinding -Findings $errors -Code 'curation_unknown_id' -Message ("No canonical {0} entity exists for id '{1}'." -f $kind, $id) -Path ("$.{0}[{1}].id" -f $field, $id)
                continue
            }
            $target = $targets[$key]
            $documentCopy = & $addDocument ([string]$target.path)
            $patch = Get-McObjectPropertyOrNull -InputObject $update -Name 'curated'
            if ($kind -eq 'project') {
                $currentCurated = Get-McObjectPropertyOrNull -InputObject $documentCopy -Name 'curated'
                Set-McObjectProperty -InputObject $documentCopy -Name 'curated' -Value (Merge-McCurationObject -Existing $currentCurated -Patch $patch)
            }
            else {
                $entities = @((Get-McObjectPropertyOrNull -InputObject $documentCopy -Name 'software'))
                $entity = Copy-McJsonObject -InputObject $entities[[int]$target.index]
                $currentCurated = Get-McObjectPropertyOrNull -InputObject $entity -Name 'curated'
                Set-McObjectProperty -InputObject $entity -Name 'curated' -Value (Merge-McCurationObject -Existing $currentCurated -Patch $patch)
                $entities[[int]$target.index] = $entity
                Set-McObjectProperty -InputObject $documentCopy -Name 'software' -Value @($entities)
            }
        }
    }

    if (Test-McCurationPropertyPresent -InputObject $document -Name 'conventions_update') {
        $conventionsPath = Join-Path $RepoRoot 'context/conventions.json'
        $conventions = & $addDocument $conventionsPath
        $update = Get-McObjectPropertyOrNull -InputObject $document -Name 'conventions_update'
        foreach ($entry in @(Get-McPropertyEntries -InputObject $update | Where-Object { [string]$_.name -ne 'evidence_refs' })) {
            $name = [string]$entry.name
            $existing = Get-McObjectPropertyOrNull -InputObject $conventions -Name $name
            if (($entry.value -is [System.Collections.IDictionary]) -or (Test-McMapping -InputObject $entry.value)) {
                Set-McObjectProperty -InputObject $conventions -Name $name -Value (Merge-McCurationObject -Existing $existing -Patch $entry.value)
            }
            else {
                Set-McObjectProperty -InputObject $conventions -Name $name -Value (Copy-McJsonObject -InputObject $entry.value)
            }
        }
    }

    if ($errors.Count -gt 0) {
        return [pscustomobject][ordered]@{ ok = $false; errors = @($errors.ToArray()); changes = @(); proposed_documents = @{}; confirmation_path = $ConfirmationPath }
    }

    $changes = [System.Collections.Generic.List[object]]::new()
    foreach ($path in @($documents.Keys | Sort-Object)) {
        $current = Read-McJson -Path $path
        $currentText = ConvertTo-McJsonText -InputObject $current
        $proposedText = ConvertTo-McJsonText -InputObject $documents[$path]
        if ($currentText -cne $proposedText) {
            [void]$changes.Add([pscustomobject][ordered]@{
                    path = $path
                    relative_path = $path.Substring($RepoRoot.Length).TrimStart('\', '/')
                    kind = if ($path -like '*\projects\*') { 'project' } elseif ($path -like '*\software\*') { 'software' } else { 'conventions' }
                })
        }
    }

    $projectUpdatesValue = Get-McObjectPropertyOrNull -InputObject $document -Name 'project_updates'
    $softwareUpdatesValue = Get-McObjectPropertyOrNull -InputObject $document -Name 'software_updates'
    return [pscustomobject][ordered]@{
        ok = $true
        errors = @()
        confirmation_path = $ConfirmationPath
        project_update_count = if ($null -eq $projectUpdatesValue) { 0 } else { @($projectUpdatesValue).Count }
        software_update_count = if ($null -eq $softwareUpdatesValue) { 0 } else { @($softwareUpdatesValue).Count }
        conventions_update = (Test-McCurationPropertyPresent -InputObject $document -Name 'conventions_update')
        changes = @($changes.ToArray())
        proposed_documents = $documents
    }
}

function Test-McCurationPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    $rootFull = ([System.IO.Path]::GetFullPath($Root)).TrimEnd('\') + '\'
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    return $pathFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-McCurationApply {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][string]$RepoRoot
    )

    if (-not $Plan.ok) { throw 'Cannot apply an invalid curation plan.' }
    $changed = @($Plan.changes)
    if ($changed.Count -eq 0) {
        return [pscustomobject][ordered]@{ applied = $false; changed_files = @(); validation = [pscustomobject][ordered]@{ ok = $true; errors = @() } }
    }

    $runId = 'curation-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssfff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runRoot = Join-Path $RepoRoot ('.local\curation\{0}' -f $runId)
    $stageContext = Join-Path $runRoot 'context'
    $stageCurrent = Join-Path $runRoot 'CURRENT.md'
    [void](New-Item -ItemType Directory -Path $stageContext -Force)
    Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'context') -Force | Copy-Item -Destination $stageContext -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'CURRENT.md') -Destination $stageCurrent -Force

    foreach ($change in $changed) {
        if (-not (Test-McCurationPathWithinRoot -Root $RepoRoot -Path ([string]$change.path))) { throw "Refusing curation path outside repository: $($change.path)" }
        $stagePath = Join-Path $runRoot ([string]$change.relative_path)
        Write-McJson -Path $stagePath -InputObject $Plan.proposed_documents[[string]$change.path]
    }
    Invoke-McRender -RepoRoot $RepoRoot -ContextRoot $stageContext -OutputPath $stageCurrent | Out-Null
    $validation = Invoke-McValidation -RepoRoot $RepoRoot -ContextRoot $stageContext -CurrentPath $stageCurrent
    if (-not $validation.ok) {
        return [pscustomobject][ordered]@{ applied = $false; changed_files = @(); validation = $validation; stage_root = $runRoot }
    }

    $backupRoot = Join-Path $runRoot 'backup'
    [void](New-Item -ItemType Directory -Path $backupRoot -Force)
    $targets = @($changed | ForEach-Object { [string]$_.path }) + @(Join-Path $RepoRoot 'CURRENT.md')
    $backedUp = [System.Collections.Generic.List[object]]::new()
    try {
        foreach ($target in $targets) {
            if (-not (Test-McCurationPathWithinRoot -Root $RepoRoot -Path $target)) { throw "Refusing target outside repository: $target" }
            $relative = $target.Substring($RepoRoot.Length).TrimStart('\', '/')
            $backup = Join-Path $backupRoot $relative
            [void](New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force)
            Copy-Item -LiteralPath $target -Destination $backup -Force
            [void]$backedUp.Add([pscustomobject]@{ target = $target; backup = $backup })
        }
        foreach ($change in $changed) {
            Copy-Item -LiteralPath (Join-Path $runRoot ([string]$change.relative_path)) -Destination ([string]$change.path) -Force
        }
        Copy-Item -LiteralPath $stageCurrent -Destination (Join-Path $RepoRoot 'CURRENT.md') -Force
    }
    catch {
        foreach ($entry in @($backedUp | Sort-Object target -Descending)) {
            Copy-Item -LiteralPath $entry.backup -Destination $entry.target -Force
        }
        throw
    }

    return [pscustomobject][ordered]@{
        applied = $true
        changed_files = @($changed.relative_path)
        validation = $validation
        stage_root = $runRoot
    }
}
