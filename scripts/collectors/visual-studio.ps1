Set-StrictMode -Version Latest

function Get-McVisualStudioKnownVsWherePaths {
    [CmdletBinding()]
    param()

    return @(
        '%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe',
        '%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe'
    )
}

function Get-McVisualStudioToolsetVersions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InstallationPath
    )

    $path = Join-Path ([Environment]::ExpandEnvironmentVariables($InstallationPath)) 'VC\Tools\MSVC'
    if (-not (Test-Path -LiteralPath $path -PathType Container -ErrorAction SilentlyContinue)) { return @() }
    return @(
        Get-ChildItem -LiteralPath $path -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { ConvertTo-McNormalizedPath -Path $_.FullName } |
            Sort-Object
    )
}

function Get-McWindowsSdkVersions {
    [CmdletBinding()]
    param()

    $versions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @(
            'HKLM:\SOFTWARE\Microsoft\Windows Kits\Installed Roots',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows Kits\Installed Roots'
        )) {
        try {
            $item = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach ($property in @($item.PSObject.Properties)) {
                if ([string]$property.Name -notmatch '^KitsRoot') { continue }
                $root = [Environment]::ExpandEnvironmentVariables([string]$property.Value)
                $include = Join-Path $root 'Include'
                if (-not (Test-Path -LiteralPath $include -PathType Container -ErrorAction SilentlyContinue)) { continue }
                foreach ($directory in @(Get-ChildItem -LiteralPath $include -Directory -ErrorAction SilentlyContinue)) {
                    [void]$versions.Add([string]$directory.Name)
                }
            }
        }
        catch {
        }
    }
    return @($versions | Sort-Object)
}

function Get-McVisualStudioObservation {
    [CmdletBinding()]
    param()

    $warnings = [System.Collections.Generic.List[string]]::new()
    $verificationEvents = [System.Collections.Generic.List[object]]::new()
    $candidates = @(Get-McHostToolCandidates -Command 'vswhere.exe' -KnownPaths (Get-McVisualStudioKnownVsWherePaths))
    if ($candidates.Count -eq 0) {
        [void]$verificationEvents.Add([pscustomobject][ordered]@{
                module = 'development'
                id = 'visual-studio'
                provider = 'visual-studio-msvc-sdk'
                verification = 'unverified'
                reason = 'vswhere-not-found'
                source_key = 'vswhere.exe'
            })
        return New-McProviderPayload -Value ([pscustomobject][ordered]@{
                development_entities = @()
                candidates = @()
            }) -Health 'unavailable' -Optional $true -CoverageComplete $false -VerificationEvents @($verificationEvents)
    }

    $primary = $candidates[0]
    $probe = Invoke-McProbe -Executable ([string]$primary.path) -Arguments @('-all', '-prerelease', '-products', '*', '-format', 'json') -Provider 'visual-studio-msvc-sdk' -ProbeName 'vswhere-instances' -TimeoutMs 10000 -OutputCapBytes 65536 -ResolutionScope 'windows-host'
    if ($probe.status -ne 'success') {
        [void]$verificationEvents.Add([pscustomobject][ordered]@{
                module = 'development'
                id = 'visual-studio'
                provider = 'visual-studio-msvc-sdk'
                verification = 'unverified'
                reason = [string]$probe.status
                source_key = 'vswhere.exe'
            })
        [void]$warnings.Add("vswhere verifier status: $($probe.status)")
        $candidate = [pscustomobject][ordered]@{
            candidate_id = New-McStableId -Kind 'command-candidate' -Identity ("visual-studio|{0}" -f $primary.path)
            kind_hint = 'ide'
            name_hint = 'Visual Studio'
            path = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
            source = 'visual-studio-msvc-sdk'
            source_key = 'vswhere.exe'
            confidence_hint = 'low'
            evidence = @([pscustomobject][ordered]@{ type = 'command_resolves'; verifier_status = [string]$probe.status })
        }
        $failureHealth = if ($probe.status -eq 'timed_out') { 'timed_out' } else { 'partial' }
        return New-McProviderPayload -Value ([pscustomobject][ordered]@{
                development_entities = @()
                candidates = @($candidate)
            }) -Health $failureHealth -Warnings @($warnings) -Optional $true -CoverageComplete $false -VerificationEvents @($verificationEvents)
    }

    $instances = @()
    try {
        $instances = @(ConvertFrom-McVsWhereJson -Text ([string]$probe.stdout))
    }
    catch {
        [void]$warnings.Add('vswhere JSON could not be parsed')
    }

    $installations = [System.Collections.Generic.List[object]]::new()
    $toolsets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($instance in @($instances)) {
        $installationPath = [string]$instance.installation_path
        if ([string]::IsNullOrWhiteSpace($installationPath)) { continue }
        $record = [ordered]@{
            installation_path = ConvertTo-McNormalizedPath -Path $installationPath
        }
        foreach ($field in @('version', 'display_name', 'product_id', 'is_complete')) {
            $property = $instance.PSObject.Properties[$field]
            if ($null -ne $property -and $null -ne $property.Value) { $record[$field] = $property.Value }
        }
        $record.msvc_toolsets = @(Get-McVisualStudioToolsetVersions -InstallationPath $installationPath)
        foreach ($toolset in @($record.msvc_toolsets)) { [void]$toolsets.Add([string]$toolset) }
        [void]$installations.Add([pscustomobject]$record)
    }

    $sdkVersions = @(Get-McWindowsSdkVersions)
    if ($installations.Count -eq 0) {
        [void]$verificationEvents.Add([pscustomobject][ordered]@{
                module = 'development'
                id = 'visual-studio'
                provider = 'visual-studio-msvc-sdk'
                verification = 'verified-absent'
                reason = 'vswhere-no-installations'
                source_key = 'vswhere'
                confidence = 'high'
            })
        [void]$warnings.Add('vswhere returned no complete Visual Studio installation')
        return New-McProviderPayload -Value ([pscustomobject][ordered]@{
                development_entities = @()
                candidates = @()
                verifier = [pscustomobject][ordered]@{ vswhere = 'success'; installation_count = 0 }
            }) -Health 'success' -Warnings @($warnings) -Optional $true -CoverageComplete $true -VerificationEvents @($verificationEvents)
    }

    $first = $installations[0]
    $firstVersion = if ($null -ne $first.PSObject.Properties['version']) { [string]$first.version } else { $null }
    $observed = [ordered]@{
        present = $true
        verification = 'verified-present'
        scope = 'windows-host'
        version = $firstVersion
        install = [ordered]@{
            root = [string]$first.installation_path
            installations = @($installations)
        }
        msvc_toolsets = @($toolsets | Sort-Object)
        windows_sdk_versions = @($sdkVersions)
        evidence = @([pscustomobject][ordered]@{
                provider = 'visual-studio-msvc-sdk'
                provider_key = 'vswhere'
                fields = @('present', 'version', 'install', 'msvc_toolsets', 'windows_sdk_versions')
                confidence = 'high'
            })
    }
    $entity = [pscustomobject][ordered]@{
        id = 'visual-studio'
        kind = 'ide'
        name = 'Visual Studio'
        observed = [pscustomobject]$observed
    }
    [void]$verificationEvents.Add([pscustomobject][ordered]@{
            module = 'development'
            id = 'visual-studio'
            provider = 'visual-studio-msvc-sdk'
            verification = 'verified-present'
            reason = 'vswhere-installation-found'
            source_key = 'vswhere'
        })
    $successHealth = if ($warnings.Count -gt 0) { 'partial' } else { 'success' }
    return New-McProviderPayload -Value ([pscustomobject][ordered]@{
            development_entities = @($entity)
            candidates = @()
        }) -Health $successHealth -ResultCount 1 -Warnings @($warnings) -Optional $true -CoverageComplete $true -VerificationEvents @($verificationEvents)
}
