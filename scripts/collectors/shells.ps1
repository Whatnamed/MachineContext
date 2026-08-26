Set-StrictMode -Version Latest

function Get-McShellObservation {
    [CmdletBinding()]
    param()

    $shells = [System.Collections.Generic.List[object]]::new()
    $resolution = [System.Collections.Generic.List[object]]::new()
    $shellCandidates = [System.Collections.Generic.List[object]]::new()
    $verificationEvents = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $failureCount = 0
    $definitions = @(
        [pscustomobject]@{ id = 'shell-pwsh'; name = 'PowerShell 7'; command = 'pwsh.exe'; args = @('--version') },
        [pscustomobject]@{ id = 'shell-windows-powershell'; name = 'Windows PowerShell'; command = 'powershell.exe'; args = @('-NoLogo', '-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') },
        [pscustomobject]@{ id = 'shell-cmd'; name = 'Command Prompt'; command = 'cmd.exe'; args = @('/c', 'ver') },
        [pscustomobject]@{ id = 'shell-ssh'; name = 'OpenSSH client'; command = 'ssh.exe'; args = @('-V') }
    )

    foreach ($definition in $definitions) {
        $commandCandidates = @(Get-McExecutableCandidates -Executable $definition.command -Scope 'windows-host')
        if ($commandCandidates.Count -eq 0) {
            [void]$verificationEvents.Add([pscustomobject][ordered]@{
                    module = 'machine.shells'
                    id = [string]$definition.id
                    provider = 'shells-path-resolution'
                    verification = 'unverified'
                    reason = 'persistent-command-not-found'
                    source_key = [string]$definition.command
                })
            continue
        }

        $primary = $commandCandidates[0]
        $probe = Invoke-McProbe -Executable $primary.path -Arguments @($definition.args) -Provider 'shells-path-resolution' -ProbeName ([string]$definition.id) -TimeoutMs 5000 -ResolutionScope 'windows-host'
        if ($probe.status -ne 'success') {
            $failureCount++
            [void]$warnings.Add("$($definition.command) verifier status: $($probe.status)")
            [void]$verificationEvents.Add([pscustomobject][ordered]@{
                    module = 'machine.shells'
                    id = [string]$definition.id
                    provider = 'shells-path-resolution'
                    verification = 'unverified'
                    reason = [string]$probe.status
                    source_key = [string]$definition.command
                })
            [void]$shellCandidates.Add([pscustomobject][ordered]@{
                    candidate_id = New-McStableId -Kind 'shell-candidate' -Identity ("{0}|{1}" -f $definition.id, $primary.path)
                    kind_hint = 'shell'
                    name_hint = [string]$definition.name
                    path = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
                    source = 'shells-path-resolution'
                    source_key = [string]$definition.command
                    confidence_hint = 'low'
                    evidence = @([pscustomobject][ordered]@{ type = 'command_resolves'; verifier_status = [string]$probe.status })
                })
            continue
        }

        [void]$verificationEvents.Add([pscustomobject][ordered]@{
                module = 'machine.shells'
                id = [string]$definition.id
                provider = 'shells-path-resolution'
                verification = 'verified-present'
                reason = 'version-probe-success'
                source_key = [string]$definition.command
            })
        $record = [ordered]@{
            id   = [string]$definition.id
            kind = 'shell'
            name = [string]$definition.name
            observed = [ordered]@{
                present = $true
                verification = 'verified-present'
                executable = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
                command_resolution = @(
                    foreach ($candidate in $commandCandidates) {
                        [pscustomobject][ordered]@{
                            executable   = ConvertTo-McNormalizedPath -Path ([string]$candidate.path)
                            command_type = [string]$candidate.command_type
                            scope        = [string]$candidate.scope
                            source       = [string]$candidate.source
                            path_index   = $candidate.path_index
                        }
                    }
                )
                evidence = @([pscustomobject][ordered]@{
                    provider = 'persistent-path'
                    provider_key = [string]$definition.command
                    fields = @('executable', 'command_resolution')
                    confidence = if ($probe.status -eq 'success') { 'high' } else { 'low' }
                })
            }
        }
        $version = Get-McProbeVersionText -Probe $probe
        if (-not [string]::IsNullOrWhiteSpace($version)) {
            $record.observed.version = $version
        }
        [void]$shells.Add([pscustomobject]$record)
    }

    foreach ($command in @('pwsh', 'powershell', 'cmd', 'bash', 'git', 'ssh', 'where')) {
        $candidates = @(Get-McExecutableCandidates -Executable $command -Scope 'windows-host')
        if ($candidates.Count -eq 0) { continue }
        [void]$resolution.Add([pscustomobject][ordered]@{
            command = $command
            scope = 'windows-host'
            resolved = ConvertTo-McNormalizedPath -Path ([string]$candidates[0].path)
            all = @($candidates | ForEach-Object { ConvertTo-McNormalizedPath -Path ([string]$_.path) })
        })
    }

    $hostEnvironment = Get-McPersistentEnvironment
    $profiles = [System.Collections.Generic.List[object]]::new()
    $userProfile = [Environment]::GetEnvironmentVariable('USERPROFILE')
    if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
        $profilePaths = @(
            (Join-Path $userProfile 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'),
            (Join-Path $userProfile 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
            (Join-Path $userProfile 'Documents\PowerShell\profile.ps1'),
            (Join-Path $userProfile 'Documents\WindowsPowerShell\profile.ps1')
        )
        foreach ($profilePath in $profilePaths) {
            $normalized = ConvertTo-McNormalizedPath -Path $profilePath
            [void]$profiles.Add([pscustomobject][ordered]@{
                path = $normalized
                exists = (Test-Path -LiteralPath $profilePath -PathType Leaf -ErrorAction SilentlyContinue)
            })
        }
    }

    $processEnvironment = Get-McCollectorProcessEnvironment
    $processResolution = [System.Collections.Generic.List[object]]::new()
    foreach ($command in @('pwsh', 'powershell', 'cmd', 'bash', 'git', 'ssh', 'where')) {
        $candidates = @(Get-McProcessExecutableCandidates -Executable $command)
        if ($candidates.Count -eq 0) { continue }
        [void]$processResolution.Add([pscustomobject][ordered]@{
            command = $command
            scope = 'collector-process'
            resolved = ConvertTo-McNormalizedPath -Path ([string]$candidates[0].path)
            all = @($candidates | ForEach-Object { ConvertTo-McNormalizedPath -Path ([string]$_.path) })
        })
    }

    $value = [pscustomobject][ordered]@{
        shells = @($shells)
        candidates = @()
        paths = [pscustomobject][ordered]@{
            scope = 'windows-host'
            machine_path = @($hostEnvironment.machine_path)
            user_path = @($hostEnvironment.user_path)
            persistent_effective_path = @($hostEnvironment.persistent_effective_path)
            machine_context_root = ConvertTo-McNormalizedPath -Path (Join-Path $PSScriptRoot '..\..') -ResolveExisting
            entry_count = @($hostEnvironment.persistent_effective_path).Count
        }
        environment = [pscustomobject][ordered]@{
            scope = 'windows-host'
            path_summary = @($hostEnvironment.persistent_effective_path)
            shell_profiles = @($profiles)
        }
        command_resolution = @($resolution | Sort-Object command)
    }
    $local = [pscustomobject][ordered]@{
        scope = 'collector-process'
        environment = $processEnvironment
        command_resolution = @($processResolution | Sort-Object command)
    }

    $health = if ($failureCount -gt 0) { 'partial' } elseif ($shells.Count -gt 0) { 'success' } else { 'partial' }
    $value.candidates = @($shellCandidates)
    return New-McProviderPayload -Value $value -Local $local -Health $health -ResultCount ($shells.Count + $resolution.Count) -Warnings @($warnings) -CoverageComplete $false -VerificationEvents @($verificationEvents)
}
