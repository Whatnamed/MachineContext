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
        'status', 'mode', 'verified_at', 'published_verification',
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
