Set-StrictMode -Version Latest

function ConvertTo-McProjectActivityTimestamp {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $parsed = [datetime]::MinValue
    $styles = [Globalization.DateTimeStyles]::AllowWhiteSpaces -bor [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    if ([datetime]::TryParse($Text.Trim(), [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed)) {
        return $parsed.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }

    return $null
}

function Get-McProjectActivityObservation {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Candidates = @()
    )

    $eligible = @($Candidates | Where-Object {
            $_.promotion_eligible -eq $true -and $_.verified -eq $true -and -not [string]::IsNullOrWhiteSpace([string]$_.path)
        } | Sort-Object id,path)
    $gitCandidates = @(Get-McExecutableCandidates -Executable 'git.exe' -Scope 'windows-host')
    $git = $gitCandidates | Select-Object -First 1
    $items = [System.Collections.Generic.List[object]]::new()

    if ($null -eq $git) {
        $local = [pscustomobject][ordered]@{
            scope = 'windows-host'
            git_resolution = 'unavailable'
            project_activity = @()
        }
        return New-McProviderPayload -Value @() -Health 'unavailable' -ResultCount 0 -Warnings @('persistent Git resolution unavailable for project activity') -CoverageComplete $false -Optional $true -Local $local
    }

    $incompleteCount = 0
    foreach ($candidate in $eligible) {
        $id = [string]$candidate.id
        $path = ConvertTo-McNormalizedPath -Path ([string]$candidate.path) -ResolveExisting
        $branchProbe = Invoke-McProbe -Executable ([string]$git.path) -Arguments @('-C', $path, 'branch', '--show-current') -Provider 'project-activity-local' -ProbeName 'git-branch' -TimeoutMs 5000 -OutputCapBytes 4096 -ResolutionScope 'windows-host'
        $commitProbe = Invoke-McProbe -Executable ([string]$git.path) -Arguments @('-C', $path, 'log', '-1', '--format=%cI') -Provider 'project-activity-local' -ProbeName 'git-last-commit' -TimeoutMs 5000 -OutputCapBytes 4096 -ResolutionScope 'windows-host'
        $statusProbe = Invoke-McProbe -Executable ([string]$git.path) -Arguments @('-C', $path, 'status', '--porcelain', '--untracked-files=no') -Provider 'project-activity-local' -ProbeName 'git-tracked-status' -TimeoutMs 5000 -OutputCapBytes 32768 -ResolutionScope 'windows-host'

        $branch = $null
        if ($branchProbe.status -eq 'success') {
            $branchText = Get-McProbeVersionText -Probe $branchProbe
            if (-not [string]::IsNullOrWhiteSpace($branchText) -and $branchText -notmatch "`0") {
                $branch = $branchText.Trim()
            }
        }

        $lastCommitAt = $null
        if ($commitProbe.status -eq 'success') {
            $lastCommitAt = ConvertTo-McProjectActivityTimestamp -Text (Get-McProbeVersionText -Probe $commitProbe)
        }

        $trackedDirty = $null
        if ($statusProbe.status -eq 'success') {
            $trackedDirty = -not [string]::IsNullOrWhiteSpace([string]$statusProbe.stdout)
        }

        $failedProbes = @(
            @(
                [pscustomobject]@{ name = 'branch'; status = [string]$branchProbe.status }
                [pscustomobject]@{ name = 'last-commit'; status = [string]$commitProbe.status }
                [pscustomobject]@{ name = 'tracked-status'; status = [string]$statusProbe.status }
            ) | Where-Object status -ne 'success'
        )
        $verification = if ($failedProbes.Count -eq 0) { 'verified' } else { 'unverified' }
        if ($verification -eq 'unverified') { $incompleteCount++ }

        [void]$items.Add([pscustomobject][ordered]@{
                id = $id
                path = $path
                branch = $branch
                last_commit_at = $lastCommitAt
                tracked_dirty = $trackedDirty
                verification = $verification
                probe_status = [pscustomobject][ordered]@{
                    branch = [string]$branchProbe.status
                    last_commit = [string]$commitProbe.status
                    tracked_status = [string]$statusProbe.status
                }
                failure_reasons = @($failedProbes | ForEach-Object { '{0}:{1}' -f $_.name, $_.status })
            })
    }

    $warnings = if ($incompleteCount -gt 0) {
        @('project activity verification incomplete for {0} eligible project(s)' -f $incompleteCount)
    }
    else {
        @()
    }
    $health = if ($incompleteCount -gt 0) { 'partial' } else { 'success' }
    $local = [pscustomobject][ordered]@{
        scope = 'windows-host'
        git_resolution = 'verified'
        git_executable = ConvertTo-McNormalizedPath -Path ([string]$git.path)
        project_activity = @($items)
    }
    return New-McProviderPayload -Value @() -Health $health -ResultCount $items.Count -Warnings $warnings -CoverageComplete $false -Optional $true -Local $local
}
