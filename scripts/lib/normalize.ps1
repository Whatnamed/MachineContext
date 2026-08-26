Set-StrictMode -Version Latest

function Get-McEnvironmentPathMap {
    [CmdletBinding()]
    param()

    $pairs = [System.Collections.Generic.List[object]]::new()
    $definitions = @(
        [pscustomobject]@{ Token = '%USERPROFILE%'; Name = 'USERPROFILE' },
        [pscustomobject]@{ Token = '%LOCALAPPDATA%'; Name = 'LOCALAPPDATA' },
        [pscustomobject]@{ Token = '%APPDATA%'; Name = 'APPDATA' },
        [pscustomobject]@{ Token = '%PROGRAMDATA%'; Name = 'PROGRAMDATA' },
        [pscustomobject]@{ Token = '%PROGRAMFILES(X86)%'; Name = 'ProgramFiles(x86)' },
        [pscustomobject]@{ Token = '%PROGRAMFILES%'; Name = 'ProgramFiles' },
        [pscustomobject]@{ Token = '%SYSTEMROOT%'; Name = 'SystemRoot' },
        [pscustomobject]@{ Token = '%WINDIR%'; Name = 'windir' },
        [pscustomobject]@{ Token = '%PUBLIC%'; Name = 'PUBLIC' },
        [pscustomobject]@{ Token = '%TEMP%'; Name = 'TEMP' },
        [pscustomobject]@{ Token = '%TMP%'; Name = 'TMP' }
    )

    foreach ($definition in $definitions) {
        $value = [Environment]::GetEnvironmentVariable($definition.Name)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$pairs.Add([pscustomobject]@{
                Token = $definition.Token
                Value = ($value.TrimEnd('\', '/'))
            })
        }
    }

    return @($pairs | Sort-Object @{ Expression = { $_.Value.Length }; Descending = $true })
}

function ConvertTo-McNormalizedPath {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Path,

        [switch]$ResolveExisting
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $value = $Path.Trim().Replace('/', '\')
    if ($ResolveExisting -and (Test-Path -LiteralPath $value -ErrorAction SilentlyContinue)) {
        try {
            $value = [System.IO.Path]::GetFullPath($value)
        }
        catch {
            # Preserve the original normalized spelling if a provider rejects it.
        }
    }

    foreach ($pair in (Get-McEnvironmentPathMap)) {
        $prefix = [string]$pair.Value
        if ($value.Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $value = [string]$pair.Token
            break
        }

        if ($value.StartsWith($prefix + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            $suffix = $value.Substring($prefix.Length).TrimStart('\')
            $value = [string]$pair.Token + '\' + $suffix
            break
        }
    }

    $value = [regex]::Replace($value, '\\{2,}', '\')
    if ($value.Length -gt 3) {
        $value = $value.TrimEnd('\')
    }

    return $value
}

function ConvertTo-McSafePathList {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Paths
    )

    $result = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @($Paths)) {
        $normalized = ConvertTo-McNormalizedPath -Path ([string]$path)
        if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $result.Contains($normalized)) {
            [void]$result.Add($normalized)
        }
    }

    return @($result | Sort-Object)
}

function ConvertTo-McSafeUrl {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return $null
    }

    $value = $Url.Trim()
    if ($value -match '^git@(?<host>[^:]+):(?<path>.+)$') {
        return ('https://{0}/{1}' -f $Matches.host.ToLowerInvariant(), $Matches.path.TrimStart('/'))
    }

    try {
        $uri = [System.Uri]$value
        if (-not $uri.IsAbsoluteUri -or [string]::IsNullOrWhiteSpace($uri.Host)) {
            return $null
        }

        $builder = [System.UriBuilder]::new($uri)
        $builder.UserName = ''
        $builder.Password = ''
        $builder.Query = ''
        $builder.Fragment = ''
        $builder.Host = $uri.Host.ToLowerInvariant()
        $safe = $builder.Uri.AbsoluteUri
        return $safe.TrimEnd('/')
    }
    catch {
        return $null
    }
}

function ConvertTo-McSafeRepositoryIdentity {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Remote
    )

    $safe = ConvertTo-McSafeUrl -Url $Remote
    if ([string]::IsNullOrWhiteSpace($safe)) {
        return $null
    }

    try {
        $uri = [Uri]$safe
        $path = $uri.AbsolutePath.Trim('/').TrimEnd('/')
        if ($path.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
            $path = $path.Substring(0, $path.Length - 4)
        }

        if ([string]::IsNullOrWhiteSpace($path)) {
            return $uri.Host.ToLowerInvariant()
        }

        return ('{0}/{1}' -f $uri.Host.ToLowerInvariant(), $path)
    }
    catch {
        return $safe
    }
}

function ConvertTo-McSafeDiagnosticText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [ValidateRange(32, 4096)]
        [int]$MaxLength = 512
    )

    if ($null -eq $Text) {
        return $null
    }

    $safe = $Text
    $safe = [regex]::Replace($safe, '(?i)(https?://|ssh://)[^\s/@:]+:[^\s/@]+@', '$1[redacted]@')
    $safe = [regex]::Replace($safe, '(?i)\b(api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret)\b\s*[:=]\s*[^\s,;]+', '$1=[redacted]')
    $safe = [regex]::Replace($safe, '(?i)\b(ghp|github_pat|sk|xox[baprs])[-_A-Za-z0-9]{8,}', '[redacted-token]')

    if ($safe.Length -gt $MaxLength) {
        return $safe.Substring(0, $MaxLength) + '...[truncated]'
    }

    return $safe
}

function Get-McSha256Hex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
}

function New-McStableId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Identity
    )

    $kindPart = [regex]::Replace($Kind.ToLowerInvariant(), '[^a-z0-9]+', '-').Trim('-')
    $identityPart = [regex]::Replace($Identity.ToLowerInvariant(), '[^a-z0-9._:-]+', '-')
    $identityPart = [regex]::Replace($identityPart, '-{2,}', '-').Trim('-')

    if ([string]::IsNullOrWhiteSpace($identityPart)) {
        $identityPart = (Get-McSha256Hex -Text $Identity).Substring(0, 16)
    }

    if ([string]::IsNullOrWhiteSpace($kindPart)) {
        return $identityPart
    }

    return "$kindPart-$identityPart"
}

function Test-McSafeId {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Id
    )

    return (-not [string]::IsNullOrWhiteSpace($Id) -and $Id -match '^[a-z0-9][a-z0-9._:-]*$')
}

function ConvertTo-McSemanticVersion {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [AllowNull()]
        [string]$EntityId
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $value = $Text.Trim()
    $versionPattern = '(?<version>v?\d+\.\d+(?:\.\d+){0,3}(?:[-+][0-9A-Za-z][0-9A-Za-z.-]*)?)'
    $patterns = @(
        ('(?i)\bgo\s+version\s+go' + $versionPattern),
        ('(?i)\b(?:python|pip|pipx|cargo|rustc|rustup|uv|uvx|gh|flutter|dart|npm|pnpm|yarn|bun|deno|ruby|php|cmake|ninja|adb|git-lfs|git|node)\b[^\d]{0,48}' + $versionPattern),
        ('(?i)\bversion\s*[=:]?\s*' + $versionPattern),
        ('(?<![A-Za-z0-9])' + $versionPattern)
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($value, $pattern)
        if (-not $match.Success) {
            continue
        }
        $version = [string]$match.Groups['version'].Value
        if ($version.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
            $version = $version.Substring(1)
        }
        if ($version -match '^\d+\.\d+(?:\.\d+){0,3}(?:[-+][0-9A-Za-z][0-9A-Za-z.-]*)?$') {
            return $version
        }
    }

    # A short, already semantic-looking value is safe to retain. Everything
    # else is intentionally dropped instead of publishing a banner that may
    # contain a path, account name, or other provider-specific details.
    if ($value.Length -le 64 -and $value -match '^v?\d+\.\d+(?:\.\d+){0,3}(?:[-+][0-9A-Za-z][0-9A-Za-z.-]*)?$') {
        return ($value -replace '^v', '')
    }
    if ($value.Length -le 64 -and $value -match '^[A-Za-z0-9][A-Za-z0-9._+-]*$') {
        return $value
    }
    return $null
}
