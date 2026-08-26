Set-StrictMode -Version Latest

function Get-McNetworkObservation {
    [CmdletBinding()]
    param()

    $warnings = [System.Collections.Generic.List[string]]::new()
    $proxy = [ordered]@{}
    $proxyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $proxyEnabled = Get-McRegistryValue -Path $proxyKey -Name 'ProxyEnable'
    if ($null -ne $proxyEnabled) {
        $proxy.enabled = ([int]$proxyEnabled -eq 1)
    }

    $proxyServer = Get-McRegistryValue -Path $proxyKey -Name 'ProxyServer'
    if (-not [string]::IsNullOrWhiteSpace([string]$proxyServer)) {
        $proxy.configured = $true
        $localEndpoints = [System.Collections.Generic.List[string]]::new()
        foreach ($match in [regex]::Matches([string]$proxyServer, '(?i)(?:localhost|127\.0\.0\.1|\[::1\])(?::\d{1,5})?')) {
            if (-not $localEndpoints.Contains($match.Value)) {
                [void]$localEndpoints.Add($match.Value)
            }
        }
        if ($localEndpoints.Count -gt 0) {
            $proxy.local_endpoints = @($localEndpoints | Sort-Object)
        }
    }

    $proxyEnvironment = [System.Collections.Generic.List[object]]::new()
    foreach ($name in @('HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            [void]$proxyEnvironment.Add([pscustomobject][ordered]@{ name = $name; configured = $true })
        }
    }
    if ($proxyEnvironment.Count -gt 0) {
        $proxy.environment_variables = @($proxyEnvironment | Sort-Object name)
    }

    $ports = [System.Collections.Generic.List[object]]::new()
    $portAllowlist = @(3000, 5432, 6379, 7988, 8000, 8080, 8787, 10100, 10808, 18080, 54321)
    try {
        $connections = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {
            $_.LocalPort -in $portAllowlist -and $_.LocalAddress -in @('127.0.0.1', '0.0.0.0', '::1', '::')
        })
        foreach ($connection in $connections) {
            [void]$ports.Add([pscustomobject][ordered]@{
                port = [int]$connection.LocalPort
                address_scope = if ($connection.LocalAddress -in @('127.0.0.1', '::1')) { 'loopback' } else { 'local-machine' }
            })
        }
    }
    catch {
        [void]$warnings.Add('Get-NetTCPConnection unavailable or access denied')
    }

    $wsl = [ordered]@{}
    $wslProbe = Invoke-McProbe -Executable 'wsl.exe' -Arguments @('--status') -Provider 'network-local-services' -ProbeName 'wsl-status' -TimeoutMs 8000 -OutputCapBytes 16384
    if ($wslProbe.status -eq 'success') {
        $wsl.present = $true
        $statusSummary = Get-McProbeVersionText -Probe $wslProbe
        if (-not [string]::IsNullOrWhiteSpace($statusSummary) -and $statusSummary -notmatch "`0") {
            $wsl.status_summary = $statusSummary
        }
        $listProbe = Invoke-McProbe -Executable 'wsl.exe' -Arguments @('--list', '--quiet') -Provider 'network-local-services' -ProbeName 'wsl-distros' -TimeoutMs 8000 -OutputCapBytes 16384
        if ($listProbe.status -eq 'success') {
            $distros = [System.Collections.Generic.List[string]]::new()
            foreach ($line in @($listProbe.stdout -split "`r?`n")) {
                $clean = ([string]$line).Replace("`0", '').Trim()
                if (-not [string]::IsNullOrWhiteSpace($clean) -and -not $distros.Contains($clean)) {
                    [void]$distros.Add($clean)
                }
            }
            $wsl.distros = @($distros | Sort-Object)
        }
    }
    elseif ($wslProbe.status -ne 'unavailable') {
        $wsl.present = $false
        [void]$warnings.Add("wsl status probe: $($wslProbe.status)")
    }

    $value = [pscustomobject][ordered]@{
        primary_network = [pscustomobject][ordered]@{
            observed = [pscustomobject][ordered]@{
                scope = 'windows-host'
                proxy_environment_names = @($proxyEnvironment | ForEach-Object name | Sort-Object -Unique)
            }
            curated = [pscustomobject][ordered]@{}
        }
        proxy = [pscustomobject][ordered]@{
            observed = [pscustomobject]$proxy
            curated = [pscustomobject][ordered]@{}
        }
        local_services = @($ports | Sort-Object port,address_scope -Unique)
        ports = @($ports | Sort-Object port,address_scope -Unique)
        wsl = [pscustomobject]$wsl
        constraints = @()
    }
    return New-McProviderPayload -Value $value -Health 'success' -ResultCount ($ports.Count + 1) -Warnings @($warnings) -CoverageComplete $false
}
