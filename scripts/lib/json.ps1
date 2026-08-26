Set-StrictMode -Version Latest

function Get-McPropertyEntries {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return @()
    }

    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive -or $InputObject -is [decimal] -or $InputObject -is [datetime]) {
        return @()
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        return @(
            foreach ($key in $InputObject.Keys) {
                [pscustomobject]@{
                    Name  = [string]$key
                    Value = $InputObject[$key]
                }
            }
        )
    }

    if ($InputObject -is [pscustomobject]) {
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

function Get-McJsonPropertyRank {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $preferred = @(
        'schema_version', 'id', 'kind', 'category', 'name', 'path', 'scope',
        'meta', 'state', 'observed', 'curated', 'present', 'version',
        'executable', 'command_resolution', 'alternative_installations',
        'install', 'config_paths', 'data_paths', 'evidence', 'origin',
        'provider', 'provider_key', 'fields', 'confidence', 'health',
        'status', 'mode', 'verified_at', 'published_verification',
        'modules', 'software', 'projects', 'relationships', 'constraints',
        'directories', 'installation', 'updates', 'principles', 'system',
        'hardware', 'storage', 'shells', 'paths', 'environment',
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

    if ($InputObject -is [string] -or $InputObject.GetType().IsPrimitive -or $InputObject -is [decimal]) {
        return $InputObject
    }

    if ($InputObject -is [System.Collections.IDictionary] -or $InputObject -is [pscustomobject]) {
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

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) {
            [void]$items.Add((ConvertTo-McStableObject -InputObject $item))
        }

        Write-Output -NoEnumerate -InputObject $items.ToArray()
        return
    }

    return $InputObject
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

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Array] -and $InputObject.Count -eq 0) {
        Write-Output -NoEnumerate -InputObject ([object[]]@())
        return
    }

    $parsed = (ConvertTo-McJsonText -InputObject $InputObject) | ConvertFrom-Json -Depth 100
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        Write-Output -NoEnumerate -InputObject @($parsed)
        return
    }

    return $parsed
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
