Set-StrictMode -Version Latest

function Get-McWindowsNormalizedFamily {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$ProductName,

        [AllowNull()]
        [string]$BuildNumber
    )

    if ([string]$ProductName -match '(?i)server') {
        return 'Windows Server'
    }

    $build = 0
    if ([int]::TryParse([string]$BuildNumber, [ref]$build)) {
        if ($build -ge 22000) { return 'Windows 11' }
        if ($build -ge 10240) { return 'Windows 10' }
    }

    if ([string]$ProductName -match '(?i)Windows') {
        return 'Windows'
    }
    return $null
}

function Get-McFirstNonEmptyLine {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    foreach ($line in @(([string]$Text) -split "`r?`n")) {
        $value = $line.Trim()
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value
        }
    }
    return $null
}

function ConvertFrom-McNvidiaSmiText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in @(([string]$Text) -split "`r?`n")) {
        $clean = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        $parts = @($clean -split '\s*,\s*', 3)
        if ($parts.Count -lt 1 -or [string]::IsNullOrWhiteSpace($parts[0])) { continue }

        $record = [ordered]@{
            name = $parts[0].Trim()
            vram_source = 'nvidia-smi'
            verification = 'verified-present'
        }
        if ($parts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) {
            $record.driver_version = $parts[1].Trim()
        }
        if ($parts.Count -ge 3) {
            $memoryMiB = 0L
            $memoryText = $parts[2].Trim() -replace '(?i)\s*MiB\s*$', ''
            if ([int64]::TryParse($memoryText, [Globalization.NumberStyles]::Integer, [Globalization.CultureInfo]::InvariantCulture, [ref]$memoryMiB) -and $memoryMiB -ge 0) {
                $record.vram_bytes = $memoryMiB * 1MB
            }
        }
        [void]$records.Add([pscustomobject]$record)
    }
    return @($records)
}

function ConvertFrom-McVsWhereJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $parsed = $Text | ConvertFrom-Json -Depth 30 -ErrorAction Stop
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($instance in @($parsed)) {
        $installationPath = [string]$instance.installationPath
        if ([string]::IsNullOrWhiteSpace($installationPath)) { continue }
        $record = [ordered]@{
            installation_path = ConvertTo-McNormalizedPath -Path $installationPath
        }
        foreach ($field in @(
                [pscustomobject]@{ source = 'installationVersion'; target = 'version' },
                [pscustomobject]@{ source = 'displayName'; target = 'display_name' },
                [pscustomobject]@{ source = 'productId'; target = 'product_id' },
                [pscustomobject]@{ source = 'isComplete'; target = 'is_complete' }
            )) {
            $property = $instance.PSObject.Properties[[string]$field.source]
            if ($null -ne $property -and $null -ne $property.Value) {
                $value = $property.Value
                if ($field.target -eq 'is_complete') { $value = [bool]$value } else { $value = [string]$value }
                $record[[string]$field.target] = $value
            }
        }
        [void]$records.Add([pscustomobject]$record)
    }
    return @($records | Sort-Object installation_path,version)
}

function ConvertFrom-McDotnetSdkText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in @(([string]$Text) -split "`r?`n")) {
        $clean = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        if ($clean -match '^(?<version>\S+)\s+\[(?<path>.+)\]$') {
            [void]$records.Add([pscustomobject][ordered]@{
                version = [string]$Matches.version
                path = ConvertTo-McNormalizedPath -Path ([string]$Matches.path)
            })
        }
        elseif ($clean -match '^(?<version>\S+)$') {
            [void]$records.Add([pscustomobject][ordered]@{ version = [string]$Matches.version })
        }
    }
    return @($records | Sort-Object version,path)
}

function ConvertFrom-McDotnetRuntimeText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($line in @(([string]$Text) -split "`r?`n")) {
        $clean = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($clean)) { continue }
        if ($clean -match '^(?<name>\S+)\s+(?<version>\S+)\s+\[(?<path>.+)\]$') {
            [void]$records.Add([pscustomobject][ordered]@{
                name = [string]$Matches.name
                version = [string]$Matches.version
                path = ConvertTo-McNormalizedPath -Path ([string]$Matches.path)
            })
        }
    }
    return @($records | Sort-Object name,version,path)
}
