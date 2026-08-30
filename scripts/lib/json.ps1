Set-StrictMode -Version Latest

function Test-McMapping {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $false
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return $true
    }

    if ($InputObject -is [System.Array] -or $InputObject -is [System.Collections.IList] -or $InputObject -is [System.Collections.IEnumerable]) {
        return $false
    }

    return ($InputObject.GetType().FullName -eq 'System.Management.Automation.PSCustomObject')
}

# Single null-safe property lookup used across the pipeline. The per-module
# Get-Mc*Property helpers delegate here so lookup semantics cannot drift.
function Get-McObjectPropertyOrNull {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
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

function Test-McSequence {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject -or $InputObject -is [string] -or $InputObject -is [char]) {
        return $false
    }

    if (Test-McMapping -InputObject $InputObject) {
        return $false
    }

    if ($InputObject.GetType().IsPrimitive -or $InputObject -is [decimal] -or $InputObject -is [datetime] -or $InputObject -is [guid] -or $InputObject -is [uri]) {
        return $false
    }

    return ($InputObject -is [System.Array] -or $InputObject -is [System.Collections.IList] -or $InputObject -is [System.Collections.IEnumerable])
}

function Test-McScalar {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $true
    }

    return ($InputObject -is [string] -or $InputObject -is [char] -or $InputObject.GetType().IsPrimitive -or $InputObject -is [decimal] -or $InputObject -is [datetime] -or $InputObject -is [guid] -or $InputObject -is [uri])
}

function Test-McLegacyCollectionMetadata {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if (-not (Test-McMapping -InputObject $InputObject)) {
        return $false
    }

    $entries = @(Get-McPropertyEntries -InputObject $InputObject)
    $names = @($entries | ForEach-Object { [string]$_.Name })
    $required = @('Count', 'IsFixedSize', 'IsReadOnly', 'LongLength', 'Rank', 'SyncRoot')
    if (@($required | Where-Object { $_ -notin $names }).Count -gt 0) {
        return $false
    }

    $allowed = @('Count', 'IsFixedSize', 'IsReadOnly', 'IsSynchronized', 'Length', 'LongLength', 'Rank', 'SyncRoot')
    if (@($names | Where-Object { $_ -notin $allowed }).Count -gt 0) {
        return $false
    }

    $syncRootEntry = $entries | Where-Object { [string]$_.Name -ceq 'SyncRoot' } | Select-Object -First 1
    return ($null -ne $syncRootEntry)
}

function ConvertFrom-McLegacyCollectionMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    $entries = @(Get-McPropertyEntries -InputObject $InputObject)
    $countEntry = $entries | Where-Object { [string]$_.Name -ceq 'Count' } | Select-Object -First 1
    $syncRootEntry = $entries | Where-Object { [string]$_.Name -ceq 'SyncRoot' } | Select-Object -First 1
    $count = 0
    if ($null -ne $countEntry) {
        [int]::TryParse([string]$countEntry.Value, [ref]$count) | Out-Null
    }

    $rawItems = @()
    if ($count -gt 0 -and $null -ne $syncRootEntry) {
        $rawItems = @($syncRootEntry.Value)
        if ($count -eq 1 -and $rawItems.Count -eq 0) {
            $rawItems = @($syncRootEntry.Value)
        }
    }
    if ($count -le 0) {
        $rawItems = @()
    }

    if ($count -gt 0 -and $rawItems.Count -gt $count) {
        $rawItems = @($rawItems | Select-Object -First $count)
    }
    while ($rawItems.Count -lt $count) {
        $rawItems += $null
    }
    return ,([object[]]$rawItems)
}

function Get-McPropertyEntries {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return @()
    }

    if (Test-McScalar -InputObject $InputObject) {
        return @()
    }

    if ((Test-McMapping -InputObject $InputObject) -and $InputObject -is [System.Collections.IDictionary]) {
        return @(
            foreach ($key in $InputObject.Keys) {
                [pscustomobject]@{
                    Name  = [string]$key
                    Value = $InputObject[$key]
                }
            }
        )
    }

    if ((Test-McMapping -InputObject $InputObject) -and $InputObject -is [pscustomobject]) {
        return @(
            foreach ($property in $InputObject.PSObject.Properties) {
                [pscustomobject]@{
                    Name  = $property.Name
                    Value = $property.Value
                }
            }
        )
    }

    return @()
}

function Copy-McValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [datetime]) {
        return $InputObject.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }

    if ($InputObject -is [guid] -or $InputObject -is [uri]) {
        return [string]$InputObject
    }

    if (Test-McLegacyCollectionMetadata -InputObject $InputObject) {
        return Copy-McValue -InputObject (ConvertFrom-McLegacyCollectionMetadata -InputObject $InputObject)
    }

    if (Test-McScalar -InputObject $InputObject) {
        return $InputObject
    }

    if (Test-McMapping -InputObject $InputObject) {
        $mapping = [ordered]@{}
        foreach ($entry in (Get-McPropertyEntries -InputObject $InputObject)) {
            $mapping[[string]$entry.Name] = Copy-McValue -InputObject $entry.Value
        }

        Write-Output -NoEnumerate -InputObject $mapping
        return
    }

    if (Test-McSequence -InputObject $InputObject) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) {
            [void]$items.Add((Copy-McValue -InputObject $item))
        }

        Write-Output -NoEnumerate -InputObject ([object[]]$items.ToArray())
        return
    }

    throw ("Unsupported value type for MachineContext JSON: {0}" -f $InputObject.GetType().FullName)
}

function Get-McJsonPropertyRank {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $preferred = @(
        'schema_version', 'id', 'kind', 'category', 'name', 'path', 'scope',
        'meta', 'state', 'observed', 'curated', 'present', 'verification', 'verification_provider', 'verification_reason', 'last_known', 'version',
        'executable', 'command_resolution', 'alternative_installations',
        'install', 'config_paths', 'data_paths', 'evidence', 'origin',
        'provider', 'provider_key', 'fields', 'confidence', 'health',
        'status', 'provider_state', 'mode', 'verified_at', 'published_verification', 'audit_closure',
        'modules', 'software', 'projects', 'relationships', 'constraints',
        'directories', 'installation', 'updates', 'principles', 'system',
        'hardware', 'storage', 'shells', 'paths', 'environment',
        'raw_product_name', 'normalized_family', 'vram_bytes', 'vram_source', 'vram_status',
        'primary_network', 'proxy', 'local_services', 'ports'
    )

    $index = [array]::IndexOf($preferred, $Name)
    if ($index -ge 0) {
        return $index
    }

    return 1000
}

function ConvertTo-McStableObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [datetime]) {
        return $InputObject.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }

    if ($InputObject -is [guid] -or $InputObject -is [uri]) {
        return [string]$InputObject
    }

    if (Test-McLegacyCollectionMetadata -InputObject $InputObject) {
        return ConvertTo-McStableObject -InputObject (ConvertFrom-McLegacyCollectionMetadata -InputObject $InputObject)
    }

    if (Test-McScalar -InputObject $InputObject) {
        return $InputObject
    }

    if (Test-McMapping -InputObject $InputObject) {
        $ordered = [ordered]@{}
        $entries = Get-McPropertyEntries -InputObject $InputObject
        $entries = @(
            $entries | Sort-Object -Property @(
                @{ Expression = { Get-McJsonPropertyRank -Name $_.Name }; Ascending = $true }
                @{ Expression = { $_.Name.ToLowerInvariant() }; Ascending = $true }
            )
        )

        foreach ($entry in $entries) {
            $ordered[$entry.Name] = ConvertTo-McStableObject -InputObject $entry.Value
        }

        Write-Output -NoEnumerate -InputObject $ordered
        return
    }

    if (Test-McSequence -InputObject $InputObject) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) {
            [void]$items.Add((ConvertTo-McStableObject -InputObject $item))
        }

        Write-Output -NoEnumerate -InputObject $items.ToArray()
        return
    }

    throw ("Unsupported value type for MachineContext JSON: {0}" -f $InputObject.GetType().FullName)
}

function ConvertTo-McJsonText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [ValidateRange(3, 100)]
        [int]$Depth = 100
    )

    $stable = ConvertTo-McStableObject -InputObject $InputObject
    $json = $stable | ConvertTo-Json -Depth $Depth
    return ($json.TrimEnd("`r", "`n") + [Environment]::NewLine)
}

function Write-McJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [AllowNull()]
        [object]$InputObject,

        [ValidateRange(3, 100)]
        [int]$Depth = 100
    )

    $parent = Split-Path -Parent -Path $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }

    $text = ConvertTo-McJsonText -InputObject $InputObject -Depth $Depth
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $text, $utf8)
}

function Read-McJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file does not exist: $Path"
    }

    $raw = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "JSON file is empty: $Path"
    }

    return $raw | ConvertFrom-Json -Depth 100
}

function Copy-McJsonObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    $copy = Copy-McValue -InputObject $InputObject
    Write-Output -NoEnumerate -InputObject $copy
}

function Get-McJsonString {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    return [string]$Value
}
