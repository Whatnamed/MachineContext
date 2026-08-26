Set-StrictMode -Version Latest

function ConvertTo-McEnvironmentPathList {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$PathValue
    )

    $result = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rawEntry in @($PathValue -split ';')) {
        if ([string]::IsNullOrWhiteSpace($rawEntry)) {
            continue
        }

        $expanded = [Environment]::ExpandEnvironmentVariables($rawEntry.Trim())
        $normalized = ConvertTo-McNormalizedPath -Path $expanded
        if ([string]::IsNullOrWhiteSpace($normalized)) {
            continue
        }
        if ($seen.Add($normalized)) {
            [void]$result.Add($normalized)
        }
    }

    return @($result)
}

function Get-McPersistentPathEntries {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$MachinePathValue,

        [AllowNull()]
        [string]$UserPathValue
    )

    $machineValue = if ($PSBoundParameters.ContainsKey('MachinePathValue')) {
        $MachinePathValue
    }
    else {
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
    }
    $userValue = if ($PSBoundParameters.ContainsKey('UserPathValue')) {
        $UserPathValue
    }
    else {
        [Environment]::GetEnvironmentVariable('Path', 'User')
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($scope in @(
            [pscustomobject]@{ name = 'machine'; value = $machineValue },
            [pscustomobject]@{ name = 'user'; value = $userValue }
        )) {
        $scopeSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $scopeIndex = 0
        foreach ($rawEntry in @(([string]$scope.value) -split ';')) {
            if ([string]::IsNullOrWhiteSpace($rawEntry)) {
                continue
            }

            $expanded = [Environment]::ExpandEnvironmentVariables($rawEntry.Trim())
            $normalized = ConvertTo-McNormalizedPath -Path $expanded
            if ([string]::IsNullOrWhiteSpace($normalized) -or -not $scopeSeen.Add($normalized)) {
                continue
            }

            [void]$entries.Add([pscustomobject][ordered]@{
                scope          = [string]$scope.name
                scope_index    = $scopeIndex
                path_index     = $null
                path           = $normalized
                expanded_path   = $expanded
            })
            $scopeIndex++
        }
    }

    $effectiveSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $effectiveIndex = 0
    foreach ($entry in $entries) {
        if ($effectiveSeen.Add([string]$entry.path)) {
            $entry.path_index = $effectiveIndex
            $effectiveIndex++
        }
    }

    return @($entries)
}

function Get-McPersistentEnvironment {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$MachinePathValue,

        [AllowNull()]
        [string]$UserPathValue
    )

    $entryParameters = @{}
    if ($PSBoundParameters.ContainsKey('MachinePathValue')) {
        $entryParameters.MachinePathValue = $MachinePathValue
    }
    if ($PSBoundParameters.ContainsKey('UserPathValue')) {
        $entryParameters.UserPathValue = $UserPathValue
    }
    $entries = @(Get-McPersistentPathEntries @entryParameters)

    $machine = @($entries | Where-Object scope -eq 'machine' | Sort-Object scope_index | ForEach-Object { $_.path })
    $user = @($entries | Where-Object scope -eq 'user' | Sort-Object scope_index | ForEach-Object { $_.path })
    $effective = @($entries | Where-Object { $null -ne $_.path_index } | Sort-Object path_index | ForEach-Object { $_.path })

    return [pscustomobject][ordered]@{
        scope                    = 'windows-host'
        machine_path             = $machine
        user_path                = $user
        persistent_effective_path = $effective
    }
}

function Get-McCollectorProcessEnvironment {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        scope       = 'collector-process'
        path_summary = @(ConvertTo-McEnvironmentPathList -PathValue ([Environment]::GetEnvironmentVariable('Path')))
    }
}

function Test-McCollectorProcessOnlyPath {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path).Replace('/', '\')
    return $expanded -match '(?i)\\\.cache\\codex-runtimes\\|\\\.codex\\tmp\\|\\codex-path\\|\\@openai\\codex-win32[^\\]*\\vendor\\'
}

function Get-McEnvironmentEntryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Entry
    )

    if ($Entry -is [string]) {
        return [Environment]::ExpandEnvironmentVariables([string]$Entry)
    }
    if ($Entry.PSObject.Properties.Name -contains 'expanded_path') {
        return [string]$Entry.expanded_path
    }
    if ($Entry.PSObject.Properties.Name -contains 'path') {
        return [Environment]::ExpandEnvironmentVariables([string]$Entry.path)
    }
    return $null
}

function Resolve-McPersistentCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Executable,

        [AllowNull()]
        [object[]]$PathEntries
    )

    $value = [Environment]::ExpandEnvironmentVariables($Executable.Trim())
    if ([string]::IsNullOrWhiteSpace($value)) {
        return @()
    }

    $hasPath = $value.IndexOf('\') -ge 0 -or $value.IndexOf('/') -ge 0 -or [System.IO.Path]::IsPathRooted($value)
    if ($hasPath) {
        if (-not (Test-Path -LiteralPath $value -PathType Leaf -ErrorAction SilentlyContinue)) {
            return @()
        }
        return @([pscustomobject][ordered]@{
            name         = [System.IO.Path]::GetFileName($value)
            path         = ConvertTo-McNormalizedPath -Path $value -ResolveExisting
            command_type = 'ExplicitPath'
            scope        = 'windows-host'
            source       = 'explicit-path'
            path_index   = $null
        })
    }

    $entries = if ($PSBoundParameters.ContainsKey('PathEntries')) {
        @($PathEntries)
    }
    else {
        @(Get-McPersistentPathEntries)
    }
    $extension = [System.IO.Path]::GetExtension($value)
    $names = if ([string]::IsNullOrWhiteSpace($extension)) {
        @(
            ('{0}.exe' -f $value)
            ('{0}.com' -f $value)
            ('{0}.cmd' -f $value)
            ('{0}.bat' -f $value)
        )
    }
    else {
        @($value)
    }

    $result = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($entries | Where-Object {
            if ($_.PSObject.Properties.Name -contains 'path_index') { $null -ne $_.path_index } else { $true }
        } | Sort-Object @{ Expression = {
                    if ($_.PSObject.Properties.Name -contains 'path_index' -and $null -ne $_.path_index) { [int]$_.path_index } else { [int]::MaxValue }
                }; Ascending = $true })) {
        $directory = Get-McEnvironmentEntryPath -Entry $entry
        if ([string]::IsNullOrWhiteSpace($directory)) {
            continue
        }
        foreach ($name in $names) {
            $candidatePath = Join-Path $directory $name
            if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf -ErrorAction SilentlyContinue)) {
                continue
            }
            $fullPath = try { [System.IO.Path]::GetFullPath($candidatePath) } catch { $candidatePath }
            if (-not $seen.Add($fullPath)) {
                continue
            }
            $pathIndex = if ($entry.PSObject.Properties.Name -contains 'path_index') { $entry.path_index } else { $null }
            [void]$result.Add([pscustomobject][ordered]@{
                name         = [System.IO.Path]::GetFileName($fullPath)
                path         = ConvertTo-McNormalizedPath -Path $fullPath -ResolveExisting
                command_type = 'PersistentApplication'
                scope        = 'windows-host'
                source       = 'persistent-path'
                path_index   = $pathIndex
            })
        }
    }

    return @($result)
}
