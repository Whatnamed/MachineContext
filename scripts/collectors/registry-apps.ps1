Set-StrictMode -Version Latest

function Get-McRegistryAppCandidates {
    [CmdletBinding()]
    param(
        [ValidateRange(100, 10000)]
        [int]$MaxResults = 5000
    )

    $candidates = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $definitions = @(
        [pscustomobject]@{ hive = [Microsoft.Win32.RegistryHive]::LocalMachine; name = 'HKLM'; view = [Microsoft.Win32.RegistryView]::Registry64; view_name = '64' },
        [pscustomobject]@{ hive = [Microsoft.Win32.RegistryHive]::LocalMachine; name = 'HKLM'; view = [Microsoft.Win32.RegistryView]::Registry32; view_name = '32' },
        [pscustomobject]@{ hive = [Microsoft.Win32.RegistryHive]::CurrentUser; name = 'HKCU'; view = [Microsoft.Win32.RegistryView]::Default; view_name = 'default' }
    )

    foreach ($definition in $definitions) {
        $base = $null
        $uninstall = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($definition.hive, $definition.view)
            $uninstall = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if ($null -eq $uninstall) { continue }

            foreach ($subName in @($uninstall.GetSubKeyNames())) {
                if ($candidates.Count -ge $MaxResults) { break }
                $subKey = $null
                try {
                    $subKey = $uninstall.OpenSubKey($subName)
                    if ($null -eq $subKey) { continue }
                    $displayName = $subKey.GetValue('DisplayName', $null)
                    if ([string]::IsNullOrWhiteSpace([string]$displayName)) { continue }
                    $systemComponent = $subKey.GetValue('SystemComponent', 0)
                    if ([int]$systemComponent -eq 1) { continue }

                    $version = $subKey.GetValue('DisplayVersion', $null)
                    $publisher = $subKey.GetValue('Publisher', $null)
                    $installLocation = $subKey.GetValue('InstallLocation', $null)
                    $installSource = $subKey.GetValue('InstallSource', $null)
                    $icon = $subKey.GetValue('DisplayIcon', $null)
                    if (-not [string]::IsNullOrWhiteSpace([string]$icon)) {
                        $icon = ([string]$icon -split ',')[0]
                    }

                    $identity = '{0}|{1}|{2}|{3}|{4}' -f ([string]$displayName).Trim(), ([string]$publisher).Trim(), ([string]$version).Trim(), ([string]$installLocation).Trim(), ([string]$subName).Trim()
                    $dedupeKey = $identity.ToLowerInvariant()
                    if (-not $seen.Add($dedupeKey)) { continue }

                    $metadata = [ordered]@{
                        display_name = ([string]$displayName).Trim()
                    }
                    if (-not [string]::IsNullOrWhiteSpace([string]$version)) { $metadata.version = ([string]$version).Trim() }
                    if (-not [string]::IsNullOrWhiteSpace([string]$publisher)) { $metadata.publisher = ([string]$publisher).Trim() }
                    if (-not [string]::IsNullOrWhiteSpace([string]$installLocation)) { $metadata.install_root = ConvertTo-McNormalizedPath -Path ([string]$installLocation) }
                    if (-not [string]::IsNullOrWhiteSpace([string]$installSource)) { $metadata.install_source = ConvertTo-McNormalizedPath -Path ([string]$installSource) }
                    if (-not [string]::IsNullOrWhiteSpace([string]$icon)) { $metadata.display_icon = ConvertTo-McNormalizedPath -Path ([string]$icon) }

                    [void]$candidates.Add([pscustomobject][ordered]@{
                        candidate_id = New-McStableId -Kind 'registry-app' -Identity ("{0}|{1}" -f $definition.name, $subName)
                        kind_hint = 'installed-app'
                        name_hint = ([string]$displayName).Trim()
                        path = if (-not [string]::IsNullOrWhiteSpace([string]$installLocation)) { ConvertTo-McNormalizedPath -Path ([string]$installLocation) } else { $null }
                        source = 'registry-uninstall'
                        source_key = "$($definition.name)/$($definition.view_name)/$subName"
                        confidence_hint = 'high'
                        metadata = [pscustomobject]$metadata
                        evidence = @([pscustomobject][ordered]@{
                            type = 'registry_entry'
                            hive = [string]$definition.name
                            view = [string]$definition.view_name
                            fields = @('display_name', 'version', 'publisher', 'install_root')
                        })
                    })
                }
                catch {
                    [void]$warnings.Add("registry subkey read failed: $subName")
                }
                finally {
                    if ($null -ne $subKey) { $subKey.Dispose() }
                }
            }
        }
        catch {
            [void]$warnings.Add("$($definition.name) $($definition.view_name) unavailable")
        }
        finally {
            if ($null -ne $uninstall) { $uninstall.Dispose() }
            if ($null -ne $base) { $base.Dispose() }
        }
    }

    $health = if ($candidates.Count -gt 0 -and $warnings.Count -gt 0) { 'partial' } elseif ($candidates.Count -eq 0 -and $warnings.Count -gt 0) { 'failed' } else { 'success' }
    return New-McProviderPayload -Value @($candidates) -Health $health -ResultCount $candidates.Count -Warnings @($warnings) -CoverageComplete ($health -eq 'success')
}

function Get-McWingetCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RawDirectory,

        [ValidateRange(50, 20000)]
        [int]$MaxResults = 5000
    )

    $winget = Resolve-McExecutable -Executable 'winget.exe'
    if ($null -eq $winget) {
        return New-McProviderPayload -Value @() -Health 'unavailable' -ResultCount 0 -Warnings @('winget is not available; Registry remains the structured installed-app baseline') -CoverageComplete $false -Optional $true
    }

    [void](New-Item -ItemType Directory -Path $RawDirectory -Force)
    $exportPath = Join-Path $RawDirectory 'winget-export.json'
    $probe = Invoke-McProbe -Executable $winget.path -Arguments @('export', '--output', $exportPath, '--include-versions', '--accept-source-agreements', '--disable-interactivity') -Provider 'winget-export' -ProbeName 'export' -TimeoutMs 20000 -OutputCapBytes 16384
    if ($probe.status -ne 'success' -or -not (Test-Path -LiteralPath $exportPath -PathType Leaf)) {
        $health = if ($probe.status -eq 'timed_out') { 'timed_out' } else { 'partial' }
        return New-McProviderPayload -Value @() -Health $health -ResultCount 0 -Warnings @('winget export did not complete; raw export remains local only') -CoverageComplete $false -Optional $true
    }

    $export = $null
    try {
        $export = Read-McJson -Path $exportPath
    }
    catch {
        return New-McProviderPayload -Value @() -Health 'partial' -ResultCount 0 -Warnings @('winget export was not valid JSON') -CoverageComplete $false -Optional $true
    }

    $packages = [System.Collections.Generic.List[object]]::new()
    $groups = @($export.Sources)
    if ($groups.Count -eq 0) {
        $groups = @([pscustomobject]@{ Packages = $export.Packages; SourceDetails = $null })
    }
    foreach ($group in $groups) {
        $sourceName = Get-McOptionalProperty -InputObject (Get-McOptionalProperty -InputObject $group -Name 'SourceDetails') -Name 'Identifier'
        foreach ($package in @(Get-McOptionalProperty -InputObject $group -Name 'Packages')) {
            if ($packages.Count -ge $MaxResults) { break }
            $packageId = Get-McOptionalProperty -InputObject $package -Name 'PackageIdentifier'
            if ([string]::IsNullOrWhiteSpace([string]$packageId)) { continue }
            $metadata = [ordered]@{ package_id = ([string]$packageId).Trim() }
            $version = Get-McOptionalProperty -InputObject $package -Name 'Version'
            if (-not [string]::IsNullOrWhiteSpace([string]$version)) { $metadata.version = ([string]$version).Trim() }
            if (-not [string]::IsNullOrWhiteSpace([string]$sourceName)) { $metadata.source = ([string]$sourceName).Trim() }
            [void]$packages.Add([pscustomobject][ordered]@{
                candidate_id = New-McStableId -Kind 'winget-app' -Identity ([string]$packageId)
                kind_hint = 'installed-app'
                name_hint = ([string]$packageId).Trim()
                path = $null
                source = 'winget'
                source_key = ([string]$packageId).Trim()
                confidence_hint = 'high'
                metadata = [pscustomobject]$metadata
                evidence = @([pscustomobject][ordered]@{
                    type = 'winget_package_match'
                    fields = @('package_id', 'version')
                })
            })
        }
    }

    return New-McProviderPayload -Value @($packages) -Health 'success' -ResultCount $packages.Count -CoverageComplete $true -Optional $true
}
