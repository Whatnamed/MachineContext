Set-StrictMode -Version Latest

function Get-McPrivacyFindingsInText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [string]$Source
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $patterns = @(
        [pscustomobject]@{ Code = 'credential_url'; Pattern = '(?i)(?:https?|ssh)://[^\s/@:]+:[^\s/@]+@' },
        [pscustomobject]@{ Code = 'token_url'; Pattern = '(?i)(?:https?|ssh)://[^\s/@]+@' },
        [pscustomobject]@{ Code = 'private_key'; Pattern = '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----' },
        [pscustomobject]@{ Code = 'known_token_prefix'; Pattern = '(?i)\b(?:ghp|github_pat|xox[baprs]|AKIA)[A-Za-z0-9_-]{8,}' },
        [pscustomobject]@{ Code = 'credential_assignment'; Pattern = '(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret)\b\s*[:=]\s*["'']?[^\s,"'']{4,}' }
    )

    foreach ($pattern in $patterns) {
        if ($Text -match $pattern.Pattern) {
            [void]$findings.Add([pscustomobject][ordered]@{
                source = $Source
                code   = $pattern.Code
            })
        }
    }

    return @($findings)
}

function Test-McPrivacySafeText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return $true
    }

    return (@(Get-McPrivacyFindingsInText -Text $Text -Source 'value').Count -eq 0)
}

function Get-McPrivacyFindingsInObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [string]$Path = '$'
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $InputObject) {
        return @()
    }

    if ($InputObject -is [string]) {
        foreach ($finding in (Get-McPrivacyFindingsInText -Text $InputObject -Source $Path)) {
            [void]$findings.Add($finding)
        }
        return @($findings)
    }

    if ($InputObject -is [System.Collections.IDictionary] -or $InputObject -is [pscustomobject]) {
        foreach ($entry in (Get-McPropertyEntries -InputObject $InputObject)) {
            foreach ($finding in (Get-McPrivacyFindingsInObject -InputObject $entry.Value -Path ($Path + '.' + $entry.Name))) {
                [void]$findings.Add($finding)
            }
        }
        return @($findings)
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $index = 0
        foreach ($item in $InputObject) {
            foreach ($finding in (Get-McPrivacyFindingsInObject -InputObject $item -Path ("{0}[{1}]" -f $Path, $index))) {
                [void]$findings.Add($finding)
            }
            $index++
        }
        return @($findings)
    }

    return @($findings)
}
