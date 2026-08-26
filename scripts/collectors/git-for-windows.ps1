Set-StrictMode -Version Latest

function Get-McGitCommandResolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Candidates
    )

    return @(
        foreach ($candidate in @($Candidates)) {
            [pscustomobject][ordered]@{
                executable   = ConvertTo-McNormalizedPath -Path ([string]$candidate.path)
                command_type = [string]$candidate.command_type
                scope        = [string]$candidate.scope
                source       = [string]$candidate.source
                path_index   = $candidate.path_index
            }
        }
    )
}

function Get-McGitForWindowsObservation {
    [CmdletBinding()]
    param()

    $warnings = [System.Collections.Generic.List[string]]::new()
    $development = [System.Collections.Generic.List[object]]::new()
    $shells = [System.Collections.Generic.List[object]]::new()
    $candidates = [System.Collections.Generic.List[object]]::new()
    $verificationEvents = [System.Collections.Generic.List[object]]::new()
    $gitCandidates = @(Get-McExecutableCandidates -Executable 'git.exe' -Scope 'windows-host')

    if ($gitCandidates.Count -eq 0) {
        [void]$verificationEvents.Add([pscustomobject][ordered]@{
                module = 'development'
                id = 'git'
                provider = 'git-for-windows'
                verification = 'unverified'
                reason = 'persistent-command-not-found'
                source_key = 'git.exe'
            })
        [void]$verificationEvents.Add([pscustomobject][ordered]@{
                module = 'machine.shells'
                id = 'shell-git-bash'
                provider = 'git-for-windows'
                verification = 'unverified'
                reason = 'git-command-not-found'
                source_key = 'git-install-root'
            })
        return New-McProviderPayload -Value ([pscustomobject][ordered]@{
                development_entities = @()
                shells = @()
                candidates = @()
            }) -Health 'unavailable' -CoverageComplete $false -VerificationEvents @($verificationEvents)
    }

    $primary = $gitCandidates[0]
    $gitProbe = Invoke-McProbe -Executable ([string]$primary.path) -Arguments @('--version') -Provider 'git-for-windows' -ProbeName 'git-version' -TimeoutMs 5000 -ResolutionScope 'windows-host'
    $gitPath = [Environment]::ExpandEnvironmentVariables([string]$primary.path)
    $gitRoot = $null
    try {
        $gitRoot = ConvertTo-McNormalizedPath -Path (Split-Path -Parent (Split-Path -Parent $gitPath))
    }
    catch {
        $gitRoot = $null
    }

    $gitObserved = $null
    if ($gitProbe.status -eq 'success') {
        [void]$verificationEvents.Add([pscustomobject][ordered]@{
                module = 'development'
                id = 'git'
                provider = 'git-for-windows'
                verification = 'verified-present'
                reason = 'version-probe-success'
                source_key = 'git.exe'
            })
        $gitObserved = [ordered]@{
            present = $true
            verification = 'verified-present'
            executable = ConvertTo-McNormalizedPath -Path $gitPath
            version = Get-McProbeVersionText -Probe $gitProbe
            scope = 'windows-host'
            command_resolution = @(Get-McGitCommandResolution -Candidates $gitCandidates)
            evidence = @([pscustomobject][ordered]@{
                    provider = 'git-for-windows'
                    provider_key = 'git.exe'
                    fields = @('present', 'version', 'executable', 'command_resolution')
                    confidence = 'high'
                })
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$gitRoot)) {
            $gitObserved.install = [ordered]@{ root = $gitRoot }
        }
        [void]$development.Add([pscustomobject][ordered]@{
                id = 'git'
                kind = 'toolchain'
                name = 'Git'
                observed = [pscustomobject]$gitObserved
            })
    }
    else {
        [void]$verificationEvents.Add([pscustomobject][ordered]@{
                module = 'development'
                id = 'git'
                provider = 'git-for-windows'
                verification = 'unverified'
                reason = [string]$gitProbe.status
                source_key = 'git.exe'
            })
        [void]$warnings.Add("git.exe verifier status: $($gitProbe.status)")
        [void]$candidates.Add([pscustomobject][ordered]@{
                candidate_id = New-McStableId -Kind 'command-candidate' -Identity ("git|{0}" -f $primary.path)
                kind_hint = 'toolchain'
                name_hint = 'Git'
                path = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
                source = 'git-for-windows'
                source_key = 'git.exe'
                confidence_hint = 'low'
                evidence = @([pscustomobject][ordered]@{ type = 'command_resolves'; verifier_status = [string]$gitProbe.status })
            })
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$gitRoot)) {
        $bashPaths = @(
            (Join-Path ([Environment]::ExpandEnvironmentVariables([string]$gitRoot)) 'bin\bash.exe'),
            (Join-Path ([Environment]::ExpandEnvironmentVariables([string]$gitRoot)) 'usr\bin\bash.exe')
        )
        $bashCandidates = @(
            foreach ($bashPath in $bashPaths) {
                if (Test-Path -LiteralPath $bashPath -PathType Leaf -ErrorAction SilentlyContinue) {
                    [pscustomobject][ordered]@{
                        path = ConvertTo-McNormalizedPath -Path $bashPath -ResolveExisting
                        command_type = 'GitForWindowsInstall'
                        scope = 'windows-host'
                        source = 'git-install-root'
                        path_index = $null
                    }
                }
            }
        )
        if ($bashCandidates.Count -gt 0) {
            $bashPrimary = $bashCandidates[0]
            $bashProbe = Invoke-McProbe -Executable ([string]$bashPrimary.path) -Arguments @('--version') -Provider 'git-for-windows' -ProbeName 'git-bash-version' -TimeoutMs 5000 -ResolutionScope 'windows-host'
            if ($bashProbe.status -eq 'success') {
                [void]$verificationEvents.Add([pscustomobject][ordered]@{
                        module = 'machine.shells'
                        id = 'shell-git-bash'
                        provider = 'git-for-windows'
                        verification = 'verified-present'
                        reason = 'version-probe-success'
                        source_key = 'git-install-root'
                    })
                $bashObserved = [ordered]@{
                    present = $true
                    verification = 'verified-present'
                    executable = ConvertTo-McNormalizedPath -Path ([string]$bashPrimary.path)
                    version = Get-McProbeVersionText -Probe $bashProbe
                    scope = 'windows-host'
                    git_root = $gitRoot
                    git_executable = ConvertTo-McNormalizedPath -Path $gitPath
                    command_resolution = @(Get-McGitCommandResolution -Candidates $bashCandidates)
                    evidence = @([pscustomobject][ordered]@{
                            provider = 'git-for-windows'
                            provider_key = 'git-install-root'
                            fields = @('present', 'version', 'executable', 'git_root', 'git_executable')
                            confidence = 'high'
                        })
                }
                [void]$shells.Add([pscustomobject][ordered]@{
                        id = 'shell-git-bash'
                        kind = 'shell'
                        name = 'Git Bash'
                        observed = [pscustomobject]$bashObserved
                    })
            }
            else {
                [void]$verificationEvents.Add([pscustomobject][ordered]@{
                        module = 'machine.shells'
                        id = 'shell-git-bash'
                        provider = 'git-for-windows'
                        verification = 'unverified'
                        reason = [string]$bashProbe.status
                        source_key = 'git-install-root'
                    })
                [void]$warnings.Add("Git Bash verifier status: $($bashProbe.status)")
                [void]$candidates.Add([pscustomobject][ordered]@{
                        candidate_id = New-McStableId -Kind 'shell-candidate' -Identity ("git-bash|{0}" -f $bashPrimary.path)
                        kind_hint = 'shell'
                        name_hint = 'Git Bash'
                        path = ConvertTo-McNormalizedPath -Path ([string]$bashPrimary.path)
                        source = 'git-for-windows'
                        source_key = 'git-install-root'
                        confidence_hint = 'low'
                        evidence = @([pscustomobject][ordered]@{ type = 'install_root_executable'; verifier_status = [string]$bashProbe.status })
                    })
            }
        }
        else {
            [void]$verificationEvents.Add([pscustomobject][ordered]@{
                    module = 'machine.shells'
                    id = 'shell-git-bash'
                    provider = 'git-for-windows'
                    verification = 'verified-absent'
                    reason = 'git-root-bash-paths-absent'
                    source_key = 'git-install-root'
                    confidence = 'high'
                })
            [void]$warnings.Add('Git Bash executable not found under the verified Git installation root')
        }
    }

    $health = if ($development.Count -gt 0 -or $shells.Count -gt 0) {
        if ($warnings.Count -gt 0) { 'partial' } else { 'success' }
    }
    elseif ($warnings.Count -gt 0) {
        'partial'
    }
    else {
        'unavailable'
    }

    return New-McProviderPayload -Value ([pscustomobject][ordered]@{
            development_entities = @($development)
            shells = @($shells)
            candidates = @($candidates)
        }) -Health $health -ResultCount ($development.Count + $shells.Count) -Warnings @($warnings) -CoverageComplete $false -VerificationEvents @($verificationEvents)
}
