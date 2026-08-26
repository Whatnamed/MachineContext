Set-StrictMode -Version Latest

function Get-McShellObservation {
    [CmdletBinding()]
    param()

    $shells = [System.Collections.Generic.List[object]]::new()
    $resolution = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $definitions = @(
        [pscustomobject]@{ id = 'shell-pwsh'; name = 'PowerShell 7'; command = 'pwsh.exe'; args = @('--version') },
        [pscustomobject]@{ id = 'shell-windows-powershell'; name = 'Windows PowerShell'; command = 'powershell.exe'; args = @('-NoLogo', '-NoProfile', '-Command', '$PSVersionTable.PSVersion.ToString()') },
        [pscustomobject]@{ id = 'shell-cmd'; name = 'Command Prompt'; command = 'cmd.exe'; args = @('/c', 'ver') },
        [pscustomobject]@{ id = 'shell-git-bash'; name = 'Git Bash'; command = 'bash.exe'; args = @('--version') },
        [pscustomobject]@{ id = 'shell-ssh'; name = 'OpenSSH client'; command = 'ssh.exe'; args = @('-V') }
    )

    foreach ($definition in $definitions) {
        $candidates = @(Get-McExecutableCandidates -Executable $definition.command)
        if ($candidates.Count -eq 0) {
            continue
        }

        $primary = $candidates[0]
        $probe = Invoke-McProbe -Executable $primary.path -Arguments @($definition.args) -Provider 'shells-path-resolution' -ProbeName ([string]$definition.id) -TimeoutMs 5000
        $record = [ordered]@{
            id   = [string]$definition.id
            kind = 'shell'
            name = [string]$definition.name
            observed = [ordered]@{
                present = ($probe.status -eq 'success')
                executable = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
                command_resolution = @(
                    foreach ($candidate in $candidates) {
                        [pscustomobject][ordered]@{
                            executable = ConvertTo-McNormalizedPath -Path ([string]$candidate.path)
                            command_type = [string]$candidate.command_type
                        }
                    }
                )
                evidence = @([pscustomobject][ordered]@{
                    provider = 'command'
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
        if ($probe.status -ne 'success') {
            [void]$warnings.Add("$($definition.command) verifier status: $($probe.status)")
        }
        [void]$shells.Add([pscustomobject]$record)
    }

    foreach ($command in @('pwsh', 'powershell', 'cmd', 'bash', 'git', 'ssh', 'where')) {
        $candidates = @(Get-McExecutableCandidates -Executable $command)
        if ($candidates.Count -eq 0) { continue }
        [void]$resolution.Add([pscustomobject][ordered]@{
            command = $command
            resolved = ConvertTo-McNormalizedPath -Path ([string]$candidates[0].path)
            all = @($candidates | ForEach-Object { ConvertTo-McNormalizedPath -Path ([string]$_.path) })
        })
    }

    $pathEntries = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @(([Environment]::GetEnvironmentVariable('Path')) -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $normalized = ConvertTo-McNormalizedPath -Path $entry
        if ($null -ne $normalized -and -not $pathEntries.Contains($normalized)) {
            [void]$pathEntries.Add($normalized)
        }
    }

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

    $value = [pscustomobject][ordered]@{
        shells = @($shells)
        paths = [pscustomobject][ordered]@{
            machine_context_root = ConvertTo-McNormalizedPath -Path (Join-Path $PSScriptRoot '..\..') -ResolveExisting
            path_entries = @($pathEntries | Sort-Object)
            entry_count = $pathEntries.Count
        }
        environment = [pscustomobject][ordered]@{
            path_summary = @($pathEntries | Sort-Object)
            shell_profiles = @($profiles)
        }
        command_resolution = @($resolution | Sort-Object command)
    }

    $health = if ($shells.Count -gt 0) { 'success' } else { 'partial' }
    return New-McProviderPayload -Value $value -Health $health -ResultCount ($shells.Count + $resolution.Count) -Warnings @($warnings) -CoverageComplete $false
}
