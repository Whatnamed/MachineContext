Set-StrictMode -Version Latest

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
        return New-McProviderPayload -Value @() -Health 'unavailable' -ResultCount 0 -Warnings @('Everything es.exe is not installed; bounded filesystem discovery remains active') -CoverageComplete $false -Optional $true
    }

    $candidates = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $roots = @(Get-McProjectSearchRoots -RepoRoot $RepoRoot | Select-Object -First 8)
    foreach ($root in $roots) {
        if ($candidates.Count -ge $MaxResults) { break }
        $probe = Invoke-McProbe -Executable $es.path -Arguments @('-n', [string]([math]::Min(100, $MaxResults - $candidates.Count)), '-path', $root, '*.git') -Provider 'everything-index' -ProbeName 'git-fingerprints' -TimeoutMs 5000 -OutputCapBytes 65536
        if ($probe.status -ne 'success') {
            [void]$warnings.Add(("Everything query failed for {0}: {1}" -f $root, $probe.status))
            continue
        }

        foreach ($line in @($probe.stdout -split "`r?`n")) {
            if ($candidates.Count -ge $MaxResults) { break }
            $rawPath = ([string]$line).Trim()
            if ([string]::IsNullOrWhiteSpace($rawPath)) { continue }
            $normalized = ConvertTo-McNormalizedPath -Path $rawPath
            if ([string]::IsNullOrWhiteSpace($normalized)) { continue }
            $projectPath = if ($rawPath.EndsWith('\.git', [System.StringComparison]::OrdinalIgnoreCase)) { Split-Path -Parent $rawPath } else { $rawPath }
            [void]$candidates.Add([pscustomobject][ordered]@{
                candidate_id = New-McStableId -Kind 'everything-candidate' -Identity $normalized
                kind_hint = 'project-or-tool'
                name_hint = (Split-Path -Leaf $projectPath)
                path = ConvertTo-McNormalizedPath -Path $projectPath
                source = 'everything-index'
                source_key = $normalized
                confidence_hint = 'low'
                evidence = @([pscustomobject][ordered]@{ type = 'filesystem_name_match'; path = $normalized })
            })
        }
    }

    $health = if ($warnings.Count -gt 0) { 'partial' } else { 'success' }
    return New-McProviderPayload -Value @($candidates) -Health $health -ResultCount $candidates.Count -Warnings @($warnings) -CoverageComplete $false -Optional $true
}
