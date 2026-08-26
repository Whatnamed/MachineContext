Set-StrictMode -Version Latest

function Get-McEverythingQueryPatterns {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject][ordered]@{ query = '*.git'; kind = 'project-or-tool'; name = $null },
        [pscustomobject][ordered]@{ query = 'node.exe'; kind = 'portable-tool'; name = 'node' },
        [pscustomobject][ordered]@{ query = 'python.exe'; kind = 'portable-tool'; name = 'python' },
        [pscustomobject][ordered]@{ query = 'git.exe'; kind = 'portable-tool'; name = 'git' },
        [pscustomobject][ordered]@{ query = 'codex.exe'; kind = 'portable-tool'; name = 'codex' },
        [pscustomobject][ordered]@{ query = 'codex.cmd'; kind = 'portable-tool'; name = 'codex' },
        [pscustomobject][ordered]@{ query = 'supabase.exe'; kind = 'portable-tool'; name = 'supabase' },
        [pscustomobject][ordered]@{ query = 'supabase.cmd'; kind = 'portable-tool'; name = 'supabase' },
        [pscustomobject][ordered]@{ query = 'flutter.bat'; kind = 'portable-tool'; name = 'flutter' },
        [pscustomobject][ordered]@{ query = 'dart.exe'; kind = 'portable-tool'; name = 'dart' },
        [pscustomobject][ordered]@{ query = 'adb.exe'; kind = 'portable-tool'; name = 'adb' },
        [pscustomobject][ordered]@{ query = 'nvcc.exe'; kind = 'portable-tool'; name = 'nvcc' },
        [pscustomobject][ordered]@{ query = 'code.cmd'; kind = 'portable-tool'; name = 'vscode' },
        [pscustomobject][ordered]@{ query = 'code.exe'; kind = 'portable-tool'; name = 'vscode' }
    )
}

function New-McEverythingCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RawPath,

        [Parameter(Mandatory)]
        [object]$Pattern,

        [Parameter(Mandatory)]
        [object]$Policy
    )

    $normalizedMatch = ConvertTo-McNormalizedPath -Path $RawPath
    if ([string]::IsNullOrWhiteSpace($normalizedMatch)) {
        return $null
    }

    if ([string]$Pattern.query -ieq '*.git') {
        $candidatePath = if ($RawPath.EndsWith('\.git', [System.StringComparison]::OrdinalIgnoreCase)) { Split-Path -Parent $RawPath } else { $RawPath }
        $normalizedPath = ConvertTo-McNormalizedPath -Path $candidatePath
        if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
            return $null
        }
        return [pscustomobject][ordered]@{
            candidate_id       = New-McStableId -Kind 'everything-project' -Identity $normalizedPath
            kind_hint           = 'project-or-tool'
            name_hint           = (Split-Path -Leaf $candidatePath)
            path                = $normalizedPath
            source              = 'everything-index'
            source_key          = $normalizedMatch
            confidence_hint     = 'low'
            verified            = $false
            promotion_eligible  = $false
            classification      = [string]$Policy.kind
            root_policy_source  = [string]$Policy.source
            evidence            = @([pscustomobject][ordered]@{
                    type           = 'filesystem_name_match'
                    path           = $normalizedMatch
                    classification = [string]$Policy.kind
                })
        }
    }

    return [pscustomobject][ordered]@{
        candidate_id       = New-McStableId -Kind 'everything-tool' -Identity $normalizedMatch
        kind_hint          = [string]$Pattern.kind
        name_hint          = [string]$Pattern.name
        path               = $normalizedMatch
        source             = 'everything-index'
        source_key         = $normalizedMatch
        confidence_hint    = 'low'
        verified           = $false
        promotion_eligible = $false
        classification     = [string]$Policy.kind
        root_policy_source = [string]$Policy.source
        evidence           = @([pscustomobject][ordered]@{
                type           = 'filesystem_name_match'
                path           = $normalizedMatch
                file_name      = (Split-Path -Leaf $RawPath)
                classification = [string]$Policy.kind
            })
    }
}

function Get-McEverythingCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [ValidateRange(10, 500)]
        [int]$MaxResults = 100
    )

    $es = Resolve-McExecutable -Executable 'es.exe'
    if ($null -eq $es) {
        return New-McProviderPayload -Value @() -Health 'unavailable' -ResultCount 0 -Warnings @('Everything es.exe is not installed; bounded filesystem discovery remains active') -CoverageComplete $false -Optional $true -Local ([pscustomobject][ordered]@{ available = $false; patterns = @((Get-McEverythingQueryPatterns).query) })
    }

    $candidates = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $policies = @(Get-McProjectRootPolicies -RepoRoot $RepoRoot)
    $roots = @(Get-McDiscoverySearchRoots -RepoRoot $RepoRoot | Select-Object -First 12)
    $patterns = @(Get-McEverythingQueryPatterns)
    foreach ($root in $roots) {
        if ($candidates.Count -ge $MaxResults) {
            break
        }
        foreach ($pattern in $patterns) {
            if ($candidates.Count -ge $MaxResults) {
                break
            }
            $remaining = [Math]::Max(1, $MaxResults - $candidates.Count)
            $probe = Invoke-McProbe -Executable $es.path -Arguments @('-n', [string]([Math]::Min(100, $remaining)), '-path', [string]$root.path, [string]$pattern.query) -Provider 'everything-index' -ProbeName ([string]$pattern.query) -TimeoutMs 5000 -OutputCapBytes 65536
            if ($probe.status -ne 'success') {
                [void]$warnings.Add(("Everything query failed for {0} ({1}): {2}" -f $root.path, $pattern.query, $probe.status))
                continue
            }

            foreach ($line in @($probe.stdout -split "`r?`n")) {
                if ($candidates.Count -ge $MaxResults) {
                    break
                }
                $rawPath = ([string]$line).Trim()
                if ([string]::IsNullOrWhiteSpace($rawPath)) {
                    continue
                }
                $policy = Get-McProjectRootPolicyForPath -Path $rawPath -Policies $policies
                $candidate = New-McEverythingCandidate -RawPath $rawPath -Pattern $pattern -Policy $policy
                if ($null -eq $candidate) {
                    continue
                }
                if ($seen.Add([string]$candidate.candidate_id)) {
                    [void]$candidates.Add($candidate)
                }
            }
        }
    }

    $health = if ($warnings.Count -gt 0) { 'partial' } else { 'success' }
    $local = [pscustomobject][ordered]@{
        available   = $true
        executable  = ConvertTo-McNormalizedPath -Path $es.path
        roots       = @($roots.path | ForEach-Object { ConvertTo-McNormalizedPath -Path $_ })
        patterns    = @($patterns.query)
        max_results = $MaxResults
    }
    return New-McProviderPayload -Value @($candidates | Sort-Object candidate_id) -Health $health -ResultCount $candidates.Count -Warnings @($warnings) -CoverageComplete $false -Optional $true -Local $local
}
