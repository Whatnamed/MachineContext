Set-StrictMode -Version Latest

function Get-McProcessExecutableCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Executable
    )

    $value = $Executable.Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return @()
    }

    if (Test-Path -LiteralPath $value -PathType Leaf -ErrorAction SilentlyContinue) {
        try {
            return @([pscustomobject]@{
                name         = [System.IO.Path]::GetFileName($value)
                path         = [System.IO.Path]::GetFullPath($value)
                command_type = 'ExplicitPath'
            })
        }
        catch {
            return @([pscustomobject]@{
                name         = [System.IO.Path]::GetFileName($value)
                path         = $value
                command_type = 'ExplicitPath'
            })
        }
    }

    $commands = @(Get-Command -Name $value -All -ErrorAction SilentlyContinue | Where-Object {
        $_.CommandType -in @('Application', 'ExternalScript') -and -not [string]::IsNullOrWhiteSpace($_.Source)
    })

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($command in $commands) {
        $path = [string]$command.Source
        if ($seen.Add($path)) {
            [void]$result.Add([pscustomobject]@{
                name         = [string]$command.Name
                path         = $path
                command_type = [string]$command.CommandType
            })
        }
    }

    return @(
        $result | Sort-Object -Property @(
            @{ Expression = {
                    switch ([System.IO.Path]::GetExtension([string]$_.path).ToLowerInvariant()) {
                        '.exe' { 0; break }
                        '.com' { 1; break }
                        '.cmd' { 2; break }
                        '.bat' { 3; break }
                        '.ps1' { 4; break }
                        default { 5 }
                    }
                }; Ascending = $true }
            @{ Expression = { [string]$_.path }; Ascending = $true }
        )
    )
}

function Get-McExecutableCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Executable,

        [ValidateSet('windows-host', 'collector-process')]
        [string]$Scope = 'windows-host'
    )

    if ($Scope -eq 'collector-process') {
        return @(Get-McProcessExecutableCandidates -Executable $Executable)
    }

    return @(Resolve-McPersistentCommand -Executable $Executable)
}

function Resolve-McExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Executable,

        [ValidateSet('windows-host', 'collector-process')]
        [string]$Scope = 'windows-host'
    )

    return @(Get-McExecutableCandidates -Executable $Executable -Scope $Scope) | Select-Object -First 1
}

function ConvertTo-McWindowsArgument {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Argument
    )

    if ($null -eq $Argument -or $Argument.Length -eq 0) {
        return '""'
    }

    $needsQuotes = ($Argument.IndexOf(' ') -ge 0 -or $Argument.IndexOf("`t") -ge 0 -or $Argument.IndexOf('"') -ge 0)
    if (-not $needsQuotes) {
        return $Argument
    }

    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }

        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }

        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }

        [void]$builder.Append($character)
    }

    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }

    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-McWindowsCommandLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Executable,

        [AllowNull()]
        [string[]]$Arguments = @()
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    [void]$parts.Add((ConvertTo-McWindowsArgument -Argument $Executable))
    foreach ($argument in @($Arguments)) {
        [void]$parts.Add((ConvertTo-McWindowsArgument -Argument ([string]$argument)))
    }

    return ($parts -join ' ')
}

function Add-McCappedOutputLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$State,

        [Parameter(Mandatory)]
        [string]$Line
    )

    if ($State.Truncated) {
        return
    }

    $addition = $Line + [Environment]::NewLine
    $encoding = [System.Text.Encoding]::UTF8
    $currentBytes = $encoding.GetByteCount($State.Builder.ToString())
    $additionBytes = $encoding.GetByteCount($addition)
    $remaining = [int]$State.CapBytes - $currentBytes

    if ($remaining -le 0) {
        $State.Truncated = $true
        return
    }

    if ($additionBytes -le $remaining) {
        [void]$State.Builder.Append($addition)
        return
    }

    $characters = [System.Text.StringBuilder]::new()
    $bytes = 0
    foreach ($character in $addition.ToCharArray()) {
        $characterBytes = $encoding.GetByteCount([char[]]@($character))
        if (($bytes + $characterBytes) -gt $remaining) {
            break
        }

        [void]$characters.Append($character)
        $bytes += $characterBytes
    }

    [void]$State.Builder.Append($characters.ToString())
    $State.Truncated = $true
}

function ConvertTo-McCappedText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text,

        [Parameter(Mandatory)]
        [int]$CapBytes
    )

    if ($null -eq $Text) {
        return [pscustomobject]@{
            text      = ''
            truncated = $false
        }
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    if ($bytes.Length -le $CapBytes) {
        return [pscustomobject]@{
            text      = $Text
            truncated = $false
        }
    }

    return [pscustomobject]@{
        text      = [System.Text.Encoding]::UTF8.GetString($bytes, 0, $CapBytes)
        truncated = $true
    }
}

function Invoke-McProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Executable,

        [AllowNull()]
        [string[]]$Arguments = @(),

        [ValidateRange(100, 120000)]
        [int]$TimeoutMs = 5000,

        [ValidateRange(1024, 1048576)]
        [int]$OutputCapBytes = 65536,

        [string]$Provider = 'unknown',
        [string]$ProbeName = 'command',
        [string]$WorkingDirectory,

        [ValidateSet('windows-host', 'collector-process')]
        [string]$ResolutionScope = 'windows-host'
    )

    $resolved = Resolve-McExecutable -Executable $Executable -Scope $ResolutionScope
    if ($null -eq $resolved) {
        return [pscustomobject][ordered]@{
            status              = 'unavailable'
            provider            = $Provider
            probe               = $ProbeName
            requested_executable = $Executable
            resolved_executable = $null
            arguments           = @($Arguments)
            exit_code           = $null
            stdout              = ''
            stderr              = ''
            output_truncated    = $false
            timed_out           = $false
            used_shell          = $false
            duration_ms         = 0
            error               = 'executable_not_found'
        }
    }

    $resolvedLaunchPath = [Environment]::ExpandEnvironmentVariables([string]$resolved.path)
    $launchFile = $resolvedLaunchPath
    $launchArguments = @($Arguments)
    $usedShell = $false
    $launcher = 'direct'
    $extension = [System.IO.Path]::GetExtension($launchFile)
    if ($extension -in @('.cmd', '.bat')) {
        $comSpecCandidate = Resolve-McExecutable -Executable 'cmd.exe' -Scope $ResolutionScope
        $comSpec = if ($null -ne $comSpecCandidate) {
            [Environment]::ExpandEnvironmentVariables([string]$comSpecCandidate.path)
        }
        else {
            [Environment]::GetEnvironmentVariable('ComSpec')
        }
        if ([string]::IsNullOrWhiteSpace($comSpec)) { $comSpec = 'cmd.exe' }

        $launchFile = $comSpec
        $launchArguments = @('/d', '/s', '/c', (ConvertTo-McWindowsCommandLine -Executable $resolvedLaunchPath -Arguments $Arguments))
        $usedShell = $true
        $launcher = 'cmd'
    }
    elseif ($extension -eq '.ps1') {
        $pwsh = Resolve-McExecutable -Executable 'pwsh.exe' -Scope $ResolutionScope
        if ($null -eq $pwsh) {
            return [pscustomobject][ordered]@{
                status               = 'unavailable'
                provider             = $Provider
                probe                = $ProbeName
                requested_executable = $Executable
                resolved_executable  = ConvertTo-McNormalizedPath -Path ([string]$resolved.path)
                arguments            = @($Arguments)
                exit_code            = $null
                stdout               = ''
                stderr               = ''
                output_truncated     = $false
                timed_out            = $false
                used_shell           = $false
                duration_ms          = 0
                error                = 'pwsh_host_not_found_for_ps1'
            }
        }

        $launchFile = [string]$pwsh.path
        $launchArguments = @('-NoLogo', '-NoProfile', '-File', $resolvedLaunchPath) + @($Arguments)
        $launcher = 'pwsh'
    }

    $process = $null
    $startedAt = [System.Diagnostics.Stopwatch]::GetTimestamp()

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $launchFile
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            $startInfo.WorkingDirectory = $WorkingDirectory
        }

        foreach ($argument in @($launchArguments)) {
            [void]$startInfo.ArgumentList.Add([string]$argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw 'process_start_returned_false'
        }

        # Read asynchronously so a noisy process cannot deadlock on a full pipe.
        # The returned strings are capped immediately after the process exits and
        # are never persisted as raw probe output.
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $exited = $process.WaitForExit($TimeoutMs)
        $timedOut = -not $exited
        if ($timedOut) {
            try {
                $process.Kill($true)
            }
            catch {
                # A process that already exited is still a timed-out probe from the caller's perspective.
            }
            try {
                [void]$process.WaitForExit(1000)
            }
            catch {
            }
        }
        else {
            [void]$process.WaitForExit()
        }

        try {
            [void]$stdoutTask.Wait(2000)
            [void]$stderrTask.Wait(2000)
        }
        catch {
        }

        $stdoutRaw = if ($stdoutTask.IsCompleted) { [string]$stdoutTask.Result } else { '' }
        $stderrRaw = if ($stderrTask.IsCompleted) { [string]$stderrTask.Result } else { '' }
        $stdoutLimited = ConvertTo-McCappedText -Text $stdoutRaw -CapBytes $OutputCapBytes
        $stderrLimited = ConvertTo-McCappedText -Text $stderrRaw -CapBytes $OutputCapBytes

        $duration = [math]::Round((([System.Diagnostics.Stopwatch]::GetTimestamp() - $startedAt) * 1000.0) / [System.Diagnostics.Stopwatch]::Frequency, 2)
        $exitCode = $null
        if ($process.HasExited) {
            $exitCode = $process.ExitCode
        }

        $status = if ($timedOut) { 'timed_out' } elseif ($exitCode -eq 0) { 'success' } else { 'failed' }
        return [pscustomobject][ordered]@{
            status               = $status
            provider             = $Provider
            probe                = $ProbeName
            requested_executable = $Executable
            resolved_executable  = ConvertTo-McNormalizedPath -Path ([string]$resolved.path)
            arguments            = @($Arguments)
            exit_code            = $exitCode
            stdout               = (ConvertTo-McSafeDiagnosticText -Text $stdoutLimited.text -MaxLength ([math]::Min(4096, $OutputCapBytes)))
            stderr               = (ConvertTo-McSafeDiagnosticText -Text $stderrLimited.text -MaxLength ([math]::Min(4096, $OutputCapBytes)))
            output_truncated     = ($stdoutLimited.truncated -or $stderrLimited.truncated)
            timed_out            = $timedOut
            used_shell           = $usedShell
            launcher             = $launcher
            duration_ms          = $duration
            error                = $null
        }
    }
    catch {
        $duration = [math]::Round((([System.Diagnostics.Stopwatch]::GetTimestamp() - $startedAt) * 1000.0) / [System.Diagnostics.Stopwatch]::Frequency, 2)
        return [pscustomobject][ordered]@{
            status               = 'failed'
            provider             = $Provider
            probe                = $ProbeName
            requested_executable = $Executable
            resolved_executable  = ConvertTo-McNormalizedPath -Path ([string]$resolved.path)
            arguments            = @($Arguments)
            exit_code            = $null
            stdout               = ''
            stderr               = ''
            output_truncated     = $false
            timed_out            = $false
            used_shell           = $usedShell
            launcher             = $launcher
            duration_ms          = $duration
            error                = (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message)
        }
    }
    finally {
        if ($null -ne $process) {
            $process.Dispose()
        }
    }
}

function Get-McProbeVersionText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Probe
    )

    if ($Probe.status -ne 'success') {
        return $null
    }

    $combined = @([string]$Probe.stdout, [string]$Probe.stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($text in $combined) {
        $line = ($text -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            return $line.Trim()
        }
    }

    return $null
}
