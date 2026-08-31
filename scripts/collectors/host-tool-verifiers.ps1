Set-StrictMode -Version Latest

function Get-McHostToolCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [AllowNull()]
        [string[]]$KnownPaths = @()
    )

    $result = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in @(Get-McExecutableCandidates -Executable $Command -Scope 'windows-host')) {
        $path = [string]$candidate.path
        if ($seen.Add($path)) { [void]$result.Add($candidate) }
    }

    foreach ($rawPath in @($KnownPaths)) {
        if ([string]::IsNullOrWhiteSpace([string]$rawPath)) { continue }
        $path = [Environment]::ExpandEnvironmentVariables([string]$rawPath)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf -ErrorAction SilentlyContinue)) { continue }
        $fullPath = try { [System.IO.Path]::GetFullPath($path) } catch { $path }
        if ($seen.Add($fullPath)) {
            [void]$result.Add([pscustomobject][ordered]@{
                    name = [System.IO.Path]::GetFileName($fullPath)
                    path = ConvertTo-McNormalizedPath -Path $fullPath -ResolveExisting
                    command_type = 'KnownInstallPath'
                    scope = 'windows-host'
                    source = 'known-install-path'
                    path_index = $null
                })
        }
    }

    return @($result)
}

function ConvertTo-McHostToolCommandResolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Candidates
    )

    return @(
        foreach ($candidate in @($Candidates)) {
            [pscustomobject][ordered]@{
                executable = ConvertTo-McNormalizedPath -Path ([string]$candidate.path)
                command_type = [string]$candidate.command_type
                scope = [string]$candidate.scope
                source = [string]$candidate.source
                path_index = $candidate.path_index
            }
        }
    )
}

function Get-McHostToolInstallRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $directory = Split-Path -Parent $expanded
    if ([string]::IsNullOrWhiteSpace($directory)) { return $null }
    $leaf = Split-Path -Leaf $directory
    if ($leaf -ieq 'bin') {
        return ConvertTo-McNormalizedPath -Path (Split-Path -Parent $directory)
    }
    if ($leaf -ieq '.bin') {
        $nodeModules = Split-Path -Parent $directory
        if ((Split-Path -Leaf $nodeModules) -ieq 'node_modules') {
            return ConvertTo-McNormalizedPath -Path (Split-Path -Parent $nodeModules)
        }
        return ConvertTo-McNormalizedPath -Path $nodeModules
    }
    return ConvertTo-McNormalizedPath -Path $directory
}

function New-McHostToolEntity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Primary,

        [Parameter(Mandatory)]
        [object[]]$Candidates,

        [Parameter(Mandatory)]
        [object]$Probe,

        [AllowNull()]
        [object]$Extras
    )

    $observed = [ordered]@{
        present = $true
        verification = if ($Probe.status -eq 'success') { 'verified-present' } else { 'unverified' }
        scope = 'windows-host'
        executable = ConvertTo-McNormalizedPath -Path ([string]$Primary.path)
        command_resolution = @(ConvertTo-McHostToolCommandResolution -Candidates $Candidates)
        evidence = @([pscustomobject][ordered]@{
                provider = 'host-authoritative-tools'
                provider_key = [string]$Id
                fields = @('present', 'version', 'executable', 'command_resolution')
                confidence = if ($Probe.status -eq 'success') { 'high' } else { 'medium' }
            })
    }
    $version = Get-McProbeVersionText -Probe $Probe
    if (-not [string]::IsNullOrWhiteSpace([string]$version)) { $observed.version = $version }
    $root = Get-McHostToolInstallRoot -Path ([string]$Primary.path)
    if (-not [string]::IsNullOrWhiteSpace([string]$root)) { $observed.install = [ordered]@{ root = $root } }
    foreach ($property in (Get-McPropertyEntries -InputObject $Extras)) {
        $observed[$property.Name] = Copy-McValue -InputObject $property.Value
    }

    return [pscustomobject][ordered]@{
        id = $Id
        kind = $Kind
        name = $Name
        observed = [pscustomobject]$observed
    }
}

function New-McHostToolCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [object]$Primary,

        [Parameter(Mandatory)]
        [object]$Probe
    )

    return [pscustomobject][ordered]@{
        candidate_id = New-McStableId -Kind 'command-candidate' -Identity ("{0}|{1}" -f $Id, $Primary.path)
        kind_hint = $Kind
        name_hint = $Name
        path = ConvertTo-McNormalizedPath -Path ([string]$Primary.path)
        source = 'host-authoritative-tools'
        source_key = $Id
        confidence_hint = 'low'
        evidence = @([pscustomobject][ordered]@{ type = 'command_resolves'; verifier_status = [string]$Probe.status })
    }
}

function Get-McCodeAppPathRoots {
    [CmdletBinding()]
    param()

    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($key in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Code.exe',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Code.exe'
        )) {
        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($property in @($item.PSObject.Properties)) {
                if ([string]$property.Name -notmatch '^(?i)\(default\)$') { continue }
                $value = [string]$property.Value
                if ([string]::IsNullOrWhiteSpace($value)) { continue }
                $expanded = [Environment]::ExpandEnvironmentVariables($value.Trim().Trim('"'))
                if (Test-Path -LiteralPath $expanded -PathType Leaf -ErrorAction SilentlyContinue) {
                    $root = Split-Path -Parent $expanded
                    if ((Split-Path -Leaf $root) -ieq 'Microsoft VS Code') {
                        [void]$roots.Add($root)
                    }
                    else {
                        [void]$roots.Add((Split-Path -Parent $root))
                    }
                }
            }
        }
        catch {
        }
    }
    return @($roots | Sort-Object -Unique)
}

function Invoke-McHostCommandVerifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Command,

        [AllowNull()]
        [string[]]$Arguments = @('--version'),

        [AllowNull()]
        [string[]]$KnownPaths = @(),

        # When set, known paths are historical hints only: if persistent host
        # PATH resolution finds nothing, a known path must never be probed into
        # the authoritative current installation. It is recorded as a
        # low-confidence candidate hint and the entity stays unverified.
        [switch]$KnownPathsAreHints,

        [AllowNull()]
        [object]$Extras
    )

    $candidates = @(Get-McHostToolCandidates -Command $Command -KnownPaths $KnownPaths)
    if ($candidates.Count -eq 0) {
        return [pscustomobject][ordered]@{
            id = $Id
            status = 'unavailable'
            candidates = @()
            entity = $null
            candidate = $null
        }
    }

    if ($KnownPathsAreHints -and @($candidates | Where-Object { [string]$_.source -ne 'known-install-path' }).Count -eq 0) {
        $hintCandidate = $null
        if ($null -ne $candidates[0]) {
            $hintCandidate = [pscustomobject][ordered]@{
                candidate_id = New-McStableId -Kind 'command-candidate' -Identity ("{0}|{1}" -f $Id, $candidates[0].path)
                kind_hint = $Kind
                name_hint = $Name
                path = ConvertTo-McNormalizedPath -Path ([string]$candidates[0].path)
                source = 'host-authoritative-tools'
                source_key = $Id
                confidence_hint = 'low'
                evidence = @([pscustomobject][ordered]@{ type = 'known_install_path_present'; exists = $true })
            }
        }
        return [pscustomobject][ordered]@{
            id = $Id
            status = 'unavailable'
            candidates = @($candidates)
            entity = $null
            candidate = $hintCandidate
        }
    }

    $primary = $candidates[0]
    $probe = Invoke-McProbe -Executable ([string]$primary.path) -Arguments @($Arguments) -Provider 'host-authoritative-tools' -ProbeName $Id -TimeoutMs 8000 -OutputCapBytes 32768 -ResolutionScope 'windows-host'
    $entity = if ($probe.status -eq 'success') {
        New-McHostToolEntity -Id $Id -Kind $Kind -Name $Name -Primary $primary -Candidates $candidates -Probe $probe -Extras $Extras
    }
    else {
        $null
    }
    $candidate = if ($probe.status -eq 'success') { $null } else { New-McHostToolCandidate -Id $Id -Kind $Kind -Name $Name -Primary $primary -Probe $probe }
    return [pscustomobject][ordered]@{
        id = $Id
        status = [string]$probe.status
        candidates = @($candidates)
        entity = $entity
        candidate = $candidate
        probe = $probe
    }
}

function Add-McHostVerificationEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Events,

        [Parameter(Mandatory)]
        [string]$Module,

        [Parameter(Mandatory)]
        [object]$Result
    )

    [void]$Events.Add([pscustomobject][ordered]@{
            module = $Module
            id = [string]$Result.id
            provider = 'host-authoritative-tools'
            verification = if ([string]$Result.status -eq 'success') { 'verified-present' } else { 'unverified' }
            reason = [string]$Result.status
            source_key = [string]$Result.id
        })
}

function Get-McDotnetVerifierResult {
    [CmdletBinding()]
    param()

    $knownPaths = @(
        '%ProgramFiles%\dotnet\dotnet.exe',
        '%ProgramFiles(x86)%\dotnet\dotnet.exe'
    )
    $candidates = @(Get-McHostToolCandidates -Command 'dotnet.exe' -KnownPaths $knownPaths)
    if ($candidates.Count -eq 0) {
        return [pscustomobject][ordered]@{ result = [pscustomobject][ordered]@{ id = 'dotnet'; status = 'unavailable'; entity = $null; candidate = $null }; checks = @() }
    }

    $primary = $candidates[0]
    $versionProbe = Invoke-McProbe -Executable ([string]$primary.path) -Arguments @('--version') -Provider 'host-authoritative-tools' -ProbeName 'dotnet-version' -TimeoutMs 8000 -OutputCapBytes 8192 -ResolutionScope 'windows-host'
    $sdkProbe = Invoke-McProbe -Executable ([string]$primary.path) -Arguments @('--list-sdks') -Provider 'host-authoritative-tools' -ProbeName 'dotnet-list-sdks' -TimeoutMs 8000 -OutputCapBytes 32768 -ResolutionScope 'windows-host'
    $runtimeProbe = Invoke-McProbe -Executable ([string]$primary.path) -Arguments @('--list-runtimes') -Provider 'host-authoritative-tools' -ProbeName 'dotnet-list-runtimes' -TimeoutMs 8000 -OutputCapBytes 32768 -ResolutionScope 'windows-host'
    $extras = [ordered]@{}
    $install = [ordered]@{}
    $root = Get-McHostToolInstallRoot -Path ([string]$primary.path)
    if (-not [string]::IsNullOrWhiteSpace([string]$root)) { $install.root = $root }
    $sdkRecords = @(
        if ($sdkProbe.status -eq 'success') { ConvertFrom-McDotnetSdkText -Text ([string]$sdkProbe.stdout) }
    )
    $runtimeRecords = @(
        if ($runtimeProbe.status -eq 'success') { ConvertFrom-McDotnetRuntimeText -Text ([string]$runtimeProbe.stdout) }
    )
    if ($sdkProbe.status -eq 'success') { $install.sdks = $sdkRecords }
    if ($runtimeProbe.status -eq 'success') { $install.runtimes = $runtimeRecords }
    if ($install.Count -gt 0) { $extras.install = $install }
    $noSdkExpected = $versionProbe.status -ne 'success' -and $sdkProbe.status -eq 'success' -and $sdkRecords.Count -eq 0
    if ($noSdkExpected) {
        $extras.sdk_state = 'absent'
        $extras.verification_note = 'dotnet --version is unavailable because no .NET SDK is installed; runtimes were checked separately'
    }
    elseif ($versionProbe.status -ne 'success') {
        $extras.verification_note = 'dotnet version probe did not succeed; executable presence is retained as unverified'
    }
    $entity = New-McHostToolEntity -Id 'dotnet' -Kind 'runtime' -Name '.NET' -Primary $primary -Candidates $candidates -Probe $versionProbe -Extras $extras
    if ($versionProbe.status -ne 'success' -and ($sdkProbe.status -eq 'success' -or $runtimeProbe.status -eq 'success')) {
        $entity.observed.verification = 'verified-present'
    }
    $statuses = @($versionProbe.status, $sdkProbe.status, $runtimeProbe.status)
    $candidate = if ($statuses -contains 'success') { $null } else { New-McHostToolCandidate -Id 'dotnet' -Kind 'runtime' -Name '.NET' -Primary $primary -Probe $versionProbe }
    return [pscustomobject][ordered]@{
        result = [pscustomobject][ordered]@{
            id = 'dotnet'
            status = if ($statuses -contains 'timed_out') { 'timed_out' } elseif (($statuses -contains 'failed') -and -not $noSdkExpected) { 'partial' } elseif ($statuses -contains 'unavailable') { 'partial' } else { 'success' }
            entity = $entity
            candidate = $candidate
        }
        checks = @(
            [pscustomobject][ordered]@{ id = 'dotnet-version'; status = [string]$versionProbe.status },
            [pscustomobject][ordered]@{ id = 'dotnet-list-sdks'; status = [string]$sdkProbe.status },
            [pscustomobject][ordered]@{ id = 'dotnet-list-runtimes'; status = [string]$runtimeProbe.status }
        )
    }
}

function Get-McCodexDesktopVerifierResult {
    [CmdletBinding()]
    param()

    try {
        $packages = @(Get-AppxPackage -Name 'OpenAI.Codex*' -ErrorAction Stop)
        $package = @($packages | Sort-Object Name, PackageFullName | Select-Object -First 1)
        if ($package.Count -eq 0) {
            return [pscustomobject][ordered]@{
                status = 'success'
                entity = $null
                check = [pscustomobject][ordered]@{ id = 'codex-desktop'; status = 'success'; found = $false }
            }
        }

        $item = $package[0]
        $observed = [ordered]@{
            present = $true
            verification = 'verified-present'
            scope = 'windows-host'
            package_name = [string]$item.Name
            package_full_name = [string]$item.PackageFullName
            version = [string]$item.Version
            evidence = @([pscustomobject][ordered]@{
                    provider = 'host-authoritative-tools'
                    provider_key = 'codex-desktop-appx'
                    fields = @('present', 'package_name', 'version', 'install_location')
                    confidence = 'high'
                })
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$item.InstallLocation)) { $observed.install_location = ConvertTo-McNormalizedPath -Path ([string]$item.InstallLocation) }
        return [pscustomobject][ordered]@{
            status = 'success'
            entity = [pscustomobject][ordered]@{ id = 'codex-desktop'; kind = 'ai-tool'; name = 'Codex Desktop'; observed = [pscustomobject]$observed }
            check = [pscustomobject][ordered]@{ id = 'codex-desktop'; status = 'success'; found = $true }
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            status = 'failed'
            entity = $null
            check = [pscustomobject][ordered]@{ id = 'codex-desktop'; status = 'failed'; found = $null; message = (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message) }
        }
    }
}

function Get-McHostAuthoritativeToolObservation {
    [CmdletBinding()]
    param()

    $warnings = [System.Collections.Generic.List[string]]::new()
    $development = [System.Collections.Generic.List[object]]::new()
    $ai = [System.Collections.Generic.List[object]]::new()
    $candidates = [System.Collections.Generic.List[object]]::new()
    $checks = [System.Collections.Generic.List[object]]::new()
    $statuses = [System.Collections.Generic.List[string]]::new()
    $verificationEvents = [System.Collections.Generic.List[object]]::new()

    $dotnet = Get-McDotnetVerifierResult
    [void]$statuses.Add([string]$dotnet.result.status)
    [void]$checks.AddRange(@($dotnet.checks))
    if ($null -ne $dotnet.result.entity) { [void]$development.Add($dotnet.result.entity) }
    if ($null -ne $dotnet.result.candidate) { [void]$candidates.Add($dotnet.result.candidate) }
    Add-McHostVerificationEvent -Events $verificationEvents -Module 'development' -Result $dotnet.result

    $codeRoots = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @(
            '%ProgramFiles%\Microsoft VS Code',
            '%LOCALAPPDATA%\Programs\Microsoft VS Code'
        )) {
        [void]$codeRoots.Add([Environment]::ExpandEnvironmentVariables($root))
    }
    foreach ($root in @(Get-McCodeAppPathRoots)) { [void]$codeRoots.Add([string]$root) }
    $codePaths = @($codeRoots | ForEach-Object { Join-Path $_ 'bin\code.cmd' } | Sort-Object -Unique)
    $code = Invoke-McHostCommandVerifier -Id 'code' -Kind 'ide-cli' -Name 'Visual Studio Code' -Command 'code' -Arguments @('--version') -KnownPaths $codePaths
    [void]$statuses.Add([string]$code.status)
    [void]$checks.Add([pscustomobject][ordered]@{ id = 'code'; status = [string]$code.status })
    if ($null -ne $code.entity) { [void]$development.Add($code.entity) }
    if ($null -ne $code.candidate) { [void]$candidates.Add($code.candidate) }
    Add-McHostVerificationEvent -Events $verificationEvents -Module 'development' -Result $code

    $supabase = Invoke-McHostCommandVerifier -Id 'supabase' -Kind 'cli' -Name 'Supabase CLI' -Command 'supabase' -Arguments @('--version')
    [void]$statuses.Add([string]$supabase.status)
    [void]$checks.Add([pscustomobject][ordered]@{ id = 'supabase'; status = [string]$supabase.status })
    if ($null -ne $supabase.entity) { [void]$development.Add($supabase.entity) }
    if ($null -ne $supabase.candidate) { [void]$candidates.Add($supabase.candidate) }
    Add-McHostVerificationEvent -Events $verificationEvents -Module 'development' -Result $supabase

    $codex = Invoke-McHostCommandVerifier -Id 'codex-cli' -Kind 'ai-tool' -Name 'Codex CLI' -Command 'codex' -Arguments @('--version') -KnownPaths @('E:\Codex\codex-cli\codex.cmd') -KnownPathsAreHints
    [void]$statuses.Add([string]$codex.status)
    [void]$checks.Add([pscustomobject][ordered]@{ id = 'codex-cli'; status = [string]$codex.status })
    if ($null -ne $codex.entity) { [void]$ai.Add($codex.entity) }
    if ($null -ne $codex.candidate) { [void]$candidates.Add($codex.candidate) }
    Add-McHostVerificationEvent -Events $verificationEvents -Module 'ai' -Result $codex

    $desktop = Get-McCodexDesktopVerifierResult
    [void]$statuses.Add([string]$desktop.status)
    [void]$checks.Add($desktop.check)
    if ($null -ne $desktop.entity) { [void]$ai.Add($desktop.entity) }
    [void]$verificationEvents.Add([pscustomobject][ordered]@{
            module = 'ai'
            id = 'codex-desktop'
            provider = 'host-authoritative-tools'
            verification = if ($desktop.check.found -eq $false) { 'verified-absent' } elseif ($desktop.status -eq 'success') { 'verified-present' } else { 'unverified' }
            reason = if ($desktop.check.found -eq $false) { 'appx-query-no-package' } else { [string]$desktop.status }
            source_key = 'codex-desktop-appx'
            confidence = if ($desktop.check.found -eq $false) { 'high' } else { 'high' }
        })

    foreach ($status in @($statuses)) {
        if ($status -in @('failed', 'partial', 'timed_out')) {
            [void]$warnings.Add("host tool verifier status: $status")
        }
    }
    $health = if ($statuses -contains 'timed_out') { 'timed_out' } elseif ($statuses -contains 'failed') { 'partial' } elseif ($statuses -contains 'partial') { 'partial' } else { 'success' }
    return New-McProviderPayload -Value ([pscustomobject][ordered]@{
            development_entities = @($development)
            ai_entities = @($ai)
            candidates = @($candidates)
        }) -Local ([pscustomobject][ordered]@{ checks = @($checks) }) -Health $health -ResultCount ($development.Count + $ai.Count) -Warnings @($warnings) -CoverageComplete $false -VerificationEvents @($verificationEvents)
}
