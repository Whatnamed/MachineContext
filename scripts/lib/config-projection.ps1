Set-StrictMode -Version Latest

# Shared helpers for source-specific, allowlisted configuration projections.
# The privacy model is "parse allowlisted fields from the real source file";
# raw config content is never copied and regex-redacted afterwards.

function Read-McConfigYamlText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [string]$Source = 'yaml'
    )

    $lines = [System.Collections.Generic.List[object]]::new()
    $lineNumber = 0
    foreach ($raw in ($Text -split "`r?`n")) {
        $lineNumber++
        if ($raw -match '^\s*#') { continue }
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        if ($raw -match '^(---|\.\.\.)\s*$') { continue }
        $indent = 0
        foreach ($character in $raw.ToCharArray()) {
            if ($character -eq "`t") { throw ("{0}: tab indentation is not supported in the MachineContext YAML subset (line {1})" -f $Source, $lineNumber) }
            if ($character -ne ' ') { break }
            $indent++
        }
        if ($indent -ge $raw.Length) { continue }
        $content = $raw.Substring($indent).TrimEnd()
        [void]$lines.Add([pscustomobject]@{ indent = $indent; content = $content; line = $lineNumber })
    }

    if ($lines.Count -eq 0) { return $null }
    $position = 0
    return (ConvertFrom-McYamlBlock -Lines @($lines) -Position ([ref]$position) -Indent $lines[0].indent -Source $Source)
}

function Read-McConfigYaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    return (Read-McConfigYamlText -Text $text -Source ([System.IO.Path]::GetFileName($Path)))
}

function ConvertFrom-McYamlScalar {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) { return $null }
    $value = $Text.Trim()
    if ($value.Length -eq 0) { return $null }
    if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') -or ($value[0] -eq "'" -and $value[$value.Length - 1] -eq "'"))) {
        return $value.Substring(1, $value.Length - 2)
    }
    $hashIndex = $value.IndexOf(' #')
    if ($hashIndex -ge 0) { $value = $value.Substring(0, $hashIndex).Trim() }
    if ($value -match '^(true|True|TRUE)$') { return $true }
    if ($value -match '^(false|False|FALSE)$') { return $false }
    if ($value -match '^(null|Null|NULL|~)$') { return $null }
    if ($value -match '^-?\d+$') { return [long]$value }
    if ($value -match '^-?\d+\.\d+$') { return [double]$value }
    return $value
}

function ConvertFrom-McYamlBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Lines,

        [Parameter(Mandatory)]
        [ref]$Position,

        [Parameter(Mandatory)]
        [int]$Indent,

        [Parameter(Mandatory)]
        [string]$Source
    )

    if ($Position.Value -ge $Lines.Count) { return $null }
    $first = $Lines[$Position.Value]
    if ($first.indent -lt $Indent) { return $null }
    if ($first.content -match '^-(?:\s|$)') {
        $result = ConvertFrom-McYamlSequence -Lines $Lines -Position $Position -Indent $first.indent -Source $Source
        return ,$result
    }
    $result = ConvertFrom-McYamlMapping -Lines $Lines -Position $Position -Indent $first.indent -Source $Source
    return ,$result
}

function ConvertFrom-McYamlMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Lines,

        [Parameter(Mandatory)]
        [ref]$Position,

        [Parameter(Mandatory)]
        [int]$Indent,

        [Parameter(Mandatory)]
        [string]$Source
    )

    $mapping = [ordered]@{}
    while ($Position.Value -lt $Lines.Count) {
        $line = $Lines[$Position.Value]
        if ($line.indent -lt $Indent) { break }
        if ($line.indent -gt $Indent) { throw ("{0}: unexpected indentation at line {1}" -f $Source, $line.line) }
        if ($line.content -match '^-(?:\s|$)') { break }
        if ($line.content -notmatch '^("[^"]+"|''[^'']+''|[^:#]+?)\s*:(?:\s+(.*))?\s*$') {
            throw ("{0}: cannot parse mapping line {1}: {2}" -f $Source, $line.line, $line.content)
        }
        $key = $Matches[1].Trim().Trim('"', "'")
        $rest = $null
        if ($Matches.Count -ge 3 -and $null -ne $Matches[2]) { $rest = $Matches[2].Trim() }
        $Position.Value++
        if ([string]::IsNullOrEmpty($rest)) {
            if ($Position.Value -lt $Lines.Count -and $Lines[$Position.Value].indent -gt $Indent) {
                $blockValue = ConvertFrom-McYamlBlock -Lines $Lines -Position $Position -Indent $Lines[$Position.Value].indent -Source $Source
                $mapping[$key] = $blockValue
            }
            elseif ($Position.Value -lt $Lines.Count -and $Lines[$Position.Value].indent -eq $Indent -and $Lines[$Position.Value].content -match '^-(?:\s|$)') {
                # Block sequences may sit at the same indent as their mapping key.
                $sequenceValue = ConvertFrom-McYamlSequence -Lines $Lines -Position $Position -Indent $Indent -Source $Source
                $mapping[$key] = $sequenceValue
            }
            else {
                $mapping[$key] = $null
            }
        }
        else {
            $mapping[$key] = ConvertFrom-McYamlScalar -Text $rest
        }
    }
    return $mapping
}

function ConvertFrom-McYamlSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Lines,

        [Parameter(Mandatory)]
        [ref]$Position,

        [Parameter(Mandatory)]
        [int]$Indent,

        [Parameter(Mandatory)]
        [string]$Source
    )

    $items = [System.Collections.Generic.List[object]]::new()
    while ($Position.Value -lt $Lines.Count) {
        $line = $Lines[$Position.Value]
        if ($line.indent -lt $Indent) { break }
        if ($line.indent -gt $Indent) { throw ("{0}: unexpected indentation at line {1}" -f $Source, $line.line) }
        if ($line.content -notmatch '^-(?:\s+(.*))?\s*$') { break }
        $rest = $null
        if ($Matches.Count -ge 2 -and $null -ne $Matches[1]) { $rest = $Matches[1].Trim() }
        $Position.Value++
        if ([string]::IsNullOrEmpty($rest)) {
            if ($Position.Value -lt $Lines.Count -and $Lines[$Position.Value].indent -gt $Indent) {
                $blockValue = ConvertFrom-McYamlBlock -Lines $Lines -Position $Position -Indent $Lines[$Position.Value].indent -Source $Source
                [void]$items.Add($blockValue)
            }
            else {
                [void]$items.Add($null)
            }
            continue
        }
        if ($rest -match '^("[^"]+"|''[^'']+''|[^:#]+?)\s*:(?:\s+.*)?\s*$') {
            # "- key: value" starts a mapping item whose remaining keys are
            # indented to the column right after the dash.
            $itemLines = [System.Collections.Generic.List[object]]::new()
            [void]$itemLines.Add([pscustomobject]@{ indent = $Indent + 2; content = $rest; line = $line.line })
            while ($Position.Value -lt $Lines.Count -and $Lines[$Position.Value].indent -gt $Indent) {
                [void]$itemLines.Add($Lines[$Position.Value])
                $Position.Value++
            }
            $itemPosition = 0
            [void]$items.Add((ConvertFrom-McYamlMapping -Lines @($itemLines) -Position ([ref]$itemPosition) -Indent ($Indent + 2) -Source $Source))
            continue
        }
        [void]$items.Add((ConvertFrom-McYamlScalar -Text $rest))
    }
    return ,([object[]]$items.ToArray())
}

function Get-McTomlTableEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$TablePrefix
    )

    # Bounded TOML reader for allowlisted tables such as [mcp_servers.*].
    # Supports string scalars, string arrays, booleans, and integers only.
    $entries = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($raw in ($Text -split "`r?`n")) {
        $line = $raw.Trim()
        if ([string]::IsNullOrEmpty($line) -or $line.StartsWith('#')) { continue }
        if ($line -match '^\[(.+)\]$') {
            $current = $null
            $header = $Matches[1].Trim()
            $parts = [System.Collections.Generic.List[string]]::new()
            foreach ($part in [regex]::Matches($header, '"[^"]*"|''[^'']*''|[^.]+')) {
                [void]$parts.Add($part.Value.Trim('''', '"'))
            }
            if ($parts.Count -eq 2 -and $parts[0] -eq $TablePrefix) {
                $current = [pscustomobject][ordered]@{ name = $parts[1]; properties = [ordered]@{} }
                [void]$entries.Add($current)
            }
            continue
        }
        if ($null -eq $current) { continue }
        if ($line -match '^([A-Za-z0-9_.-]+)\s*=\s*(.+?)\s*$') {
            $key = $Matches[1]
            $valueText = $Matches[2]
            if ($valueText -match '^"((?:[^"\\]|\\.)*)"$') {
                $current.properties[$key] = ($Matches[1] -replace '\\\\', '\' -replace '\\"', '"')
            }
            elseif ($valueText -match "^'([^']*)'$") {
                $current.properties[$key] = $Matches[1]
            }
            elseif ($valueText -match '^\[(.*)\]$') {
                $items = [System.Collections.Generic.List[object]]::new()
                foreach ($match in [regex]::Matches($Matches[1], '"((?:[^"\\]|\\.)*)"')) {
                    [void]$items.Add(($match.Groups[1].Value -replace '\\\\', '\' -replace '\\"', '"'))
                }
                $current.properties[$key] = @($items)
            }
            elseif ($valueText -match '^(true|false)$') {
                $current.properties[$key] = ($valueText -eq 'true')
            }
            elseif ($valueText -match '^-?\d+$') {
                $current.properties[$key] = [long]$valueText
            }
        }
    }
    return @($entries)
}

function Test-McSensitiveConfigKeyName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $normalized = ($Name -replace '[-_ ]', '').ToLowerInvariant()
    $deniedExact = @(
        'apikey', 'apikeyenv', 'apikeys', 'apikeypool', 'token', 'accesstoken', 'refreshtoken',
        'secret', 'clientsecret', 'password', 'passwd', 'authorization', 'auth', 'cookie',
        'oauth', 'credential', 'credentials', 'sessionid', 'privatekey', 'bearertoken'
    )
    if ($normalized -in $deniedExact) { return $true }
    if ($normalized -match '(?i)(?:apikey|accesstoken|refreshtoken|secret|password|credential|cookie|token)$') { return $true }
    return $false
}

function Test-McEnvVarNameShape {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    return ($Value -cmatch '^[A-Z][A-Z0-9_]*[A-Z0-9]$' -and $Value.Length -ge 3)
}

function Find-McUnsafeProjectedText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    # Defense in depth for allowlisted projections: reject strings that look
    # like secrets even when the containing key was allowlisted.
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if ($Text -match '(?i)(?:https?|ssh)://[^\s/@:]+:[^\s/@]+@') { return 'credential_url' }
    if ($Text -match '(?i)(?:https?|ssh)://[^\s/@]+@') { return 'token_url' }
    if ($Text -match '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----') { return 'private_key' }
    if ($Text -match '(?i)\b(?:ghp|github_pat|xox[baprs]|AKIA|sk-)[A-Za-z0-9_-]{8,}') { return 'known_token_prefix' }
    if ($Text -match '(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret)\b\s*[:=]\s*[^\s,;'']{4,}') { return 'credential_assignment' }
    if ($Text -match '(?i)(?:^|[?&])(?:token|api[_-]?key|access[_-]?token|sig|signature)=[^\s&]{4,}') { return 'credential_query_parameter' }
    return $null
}

function Add-McProjectionRedaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Redactions,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Reason
    )

    [void]$Redactions.Add([pscustomobject][ordered]@{
        path   = $Path
        reason = $Reason
    })
}

function ConvertTo-McSafeProjectionValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Redactions,

        [AllowNull()]
        [string[]]$EnvReferenceKeys = @(),

        [int]$Depth = 0
    )

    if ($Depth -gt 12) {
        Add-McProjectionRedaction -Redactions $Redactions -Path $Path -Reason 'depth-limit'
        return $null
    }
    if ($null -eq $Value) { return $null }
    if ($Value -is [bool] -or $Value -is [long] -or $Value -is [int] -or $Value -is [double]) { return $Value }
    if ($Value -is [string]) {
        $finding = Find-McUnsafeProjectedText -Text $Value
        if ($null -ne $finding) {
            Add-McProjectionRedaction -Redactions $Redactions -Path $Path -Reason $finding
            return $null
        }
        return $Value
    }
    if (Test-McMapping -InputObject $Value) {
        $mapping = [ordered]@{}
        foreach ($entry in (Get-McPropertyEntries -InputObject $Value)) {
            $entryPath = "{0}.{1}" -f $Path, $entry.Name
            $entryKey = ([string]$entry.Name -replace '[-_ ]', '').ToLowerInvariant()
            if ($entryKey -in @($EnvReferenceKeys)) {
                # Credential fields may only survive as an environment-variable
                # NAME, renamed to a safe property so no secret-named key is
                # ever published.
                $reference = ConvertTo-McCredentialReferenceValue -Value ([string]$entry.Value) -Redactions $Redactions -Path $entryPath
                if (-not [string]::IsNullOrWhiteSpace($reference)) { $mapping['credentialEnvName'] = $reference }
                continue
            }
            if (Test-McSensitiveConfigKeyName -Name ([string]$entry.Name)) {
                Add-McProjectionRedaction -Redactions $Redactions -Path $entryPath -Reason 'sensitive-key'
                continue
            }
            $projected = ConvertTo-McSafeProjectionValue -Value $entry.Value -Path $entryPath -Redactions $Redactions -EnvReferenceKeys $EnvReferenceKeys -Depth ($Depth + 1)
            if ($null -ne $projected) { $mapping[[string]$entry.Name] = $projected }
        }
        return $mapping
    }
    if (Test-McSequence -InputObject $Value) {
        $items = [System.Collections.Generic.List[object]]::new()
        $index = 0
        foreach ($item in $Value) {
            $projected = ConvertTo-McSafeProjectionValue -Value $item -Path ("{0}[{1}]" -f $Path, $index) -Redactions $Redactions -EnvReferenceKeys $EnvReferenceKeys -Depth ($Depth + 1)
            if ($null -ne $projected) { [void]$items.Add($projected) }
            $index++
        }
        Write-Output -NoEnumerate -InputObject ([object[]]$items.ToArray())
        return
    }
    Add-McProjectionRedaction -Redactions $Redactions -Path $Path -Reason 'unsupported-value'
    return $null
}

function ConvertTo-McProjectionSafeUrl {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Url,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Redactions,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    $sanitized = ConvertTo-McSafeUrl -Url $Url
    if ([string]::IsNullOrWhiteSpace($sanitized)) {
        Add-McProjectionRedaction -Redactions $Redactions -Path $Path -Reason 'unparseable-url'
        return $null
    }
    foreach ($pattern in @('[^\s/@:]+:[^\s/@]+@', '\?')) {
        if ($Url -match $pattern) {
            Add-McProjectionRedaction -Redactions $Redactions -Path $Path -Reason 'url-sanitized'
            break
        }
    }
    return $sanitized
}

function ConvertTo-McCredentialReferenceValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Redactions,

        [Parameter(Mandatory)]
        [string]$Path
    )

    # A credential field may only survive as an environment-variable NAME.
    if (Test-McEnvVarNameShape -Value $Value) { return $Value }
    Add-McProjectionRedaction -Redactions $Redactions -Path $Path -Reason 'credential-value'
    return $null
}

function Test-McSafeMcpArgument {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Argument
    )

    if ([string]::IsNullOrWhiteSpace($Argument)) { return $false }
    if ($Argument.Length -gt 512) { return $false }
    if ($null -ne (Find-McUnsafeProjectedText -Text $Argument)) { return $false }
    if ($Argument -match '(?i)--?[A-Za-z0-9_-]*(?:token|key|secret|password)[A-Za-z0-9_-]*=') { return $false }
    return $true
}

function New-McConfigSourceFileRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('yaml', 'json', 'toml', 'env', 'sqlite', 'other')]
        [string]$Format,

        [Parameter(Mandatory)]
        [string]$Role
    )

    $exists = Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    return [pscustomobject][ordered]@{
        path   = (ConvertTo-McNormalizedPath -Path $Path)
        format = $Format
        exists = [bool]$exists
        role   = $Role
    }
}

function New-McConfigProfileRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Tool,

        [AllowNull()]
        [string]$ConfigRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [object[]]$Files,

        [AllowNull()]
        [object]$Projection,

        [AllowNull()]
        [object[]]$Redactions = @(),

        [AllowNull()]
        [string[]]$CredentialEnvNames = @(),

        [string]$ValueBasis = 'configured-local',

        [AllowNull()]
        [string]$WireVerification = $null,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Evidence
    )

    $observed = [ordered]@{
        value_basis = $ValueBasis
        projection  = $Projection
    }
    if (@($CredentialEnvNames).Count -gt 0) {
        $observed['credential_env_names'] = @($CredentialEnvNames | Sort-Object -Unique)
    }
    $observed['redactions'] = @($Redactions)
    $observed['evidence'] = @($Evidence)
    if (-not [string]::IsNullOrWhiteSpace($WireVerification)) {
        $observed['wire_verification'] = $WireVerification
    }

    return [pscustomobject][ordered]@{
        schema_version = 1
        id             = $Id
        kind           = 'ai-config-profile'
        tool           = $Tool
        source         = [pscustomobject][ordered]@{
            config_root = $ConfigRoot
            files       = @($Files)
        }
        observed       = [pscustomobject]$observed
        curated        = [pscustomobject][ordered]@{}
    }
}

function Get-McSensitiveConfigKeyFindings {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [string]$Path = '$'
    )

    # Validator-grade scan: a published config projection must never contain a
    # credential-named property, even nested inside an allowlisted subtree.
    $findings = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $InputObject) { return @($findings) }
    if ($InputObject -is [string]) { return @($findings) }
    if ($InputObject -is [System.Collections.IDictionary] -or $InputObject -is [pscustomobject]) {
        foreach ($entry in (Get-McPropertyEntries -InputObject $InputObject)) {
            $entryPath = "{0}.{1}" -f $Path, $entry.Name
            if (Test-McSensitiveConfigKeyName -Name ([string]$entry.Name)) {
                [void]$findings.Add([pscustomobject][ordered]@{ path = $entryPath; name = [string]$entry.Name })
            }
            foreach ($finding in (Get-McSensitiveConfigKeyFindings -InputObject $entry.Value -Path $entryPath)) {
                [void]$findings.Add($finding)
            }
        }
        return @($findings)
    }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        $index = 0
        foreach ($item in $InputObject) {
            foreach ($finding in (Get-McSensitiveConfigKeyFindings -InputObject $item -Path ("{0}[{1}]" -f $Path, $index))) {
                [void]$findings.Add($finding)
            }
            $index++
        }
    }
    return @($findings)
}
