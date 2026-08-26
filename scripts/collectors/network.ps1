Set-StrictMode -Version Latest

function Get-McServiceExecutableName {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$PathName
    )

    if ([string]::IsNullOrWhiteSpace($PathName)) { return $null }
    $match = [regex]::Match(
        $PathName,
        '^\s*"?([^"]+?\.exe)(?:"|\s|$)',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    if (-not $match.Success) { return $null }
    return [System.IO.Path]::GetFileName($match.Groups[1].Value)
}

function Get-McNetworkOwnershipDiagnostic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$ProcessId
    )

    $diagnostic = [ordered]@{
        parent_process_name = $null
        parent_process_path_available = $false
        service_name = $null
        service_state = $null
        service_start_mode = $null
        service_executable_name = $null
        service_executable_path_available = $false
    }
    if ($ProcessId -le 0) {
        return [pscustomobject]$diagnostic
    }

    try {
        $process = Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId={0}" -f $ProcessId) -ErrorAction Stop
        if ($null -eq $process) { return [pscustomobject]$diagnostic }
        $parentPid = [int]$process.ParentProcessId
        if ($parentPid -le 0) { return [pscustomobject]$diagnostic }

        $parent = Get-CimInstance -ClassName Win32_Process -Filter ("ProcessId={0}" -f $parentPid) -ErrorAction SilentlyContinue
        if ($null -ne $parent) {
            $diagnostic.parent_process_name = [string]$parent.Name
            $diagnostic.parent_process_path_available = -not [string]::IsNullOrWhiteSpace([string]$parent.ExecutablePath)
        }

        $service = Get-CimInstance -ClassName Win32_Service -Filter ("ProcessId={0}" -f $parentPid) -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $service) {
            $diagnostic.service_name = [string]$service.Name
            $diagnostic.service_state = [string]$service.State
            $diagnostic.service_start_mode = [string]$service.StartMode
            $diagnostic.service_executable_name = Get-McServiceExecutableName -PathName ([string]$service.PathName)
            $diagnostic.service_executable_path_available = -not [string]::IsNullOrWhiteSpace([string]$service.PathName)
        }
    }
    catch {
        # Parent/service ownership is optional local evidence. Access failures
        # must not change listener presence or provider health.
    }

    return [pscustomobject]$diagnostic
}

function Get-McNetworkListenerDiagnostics {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Connections = @()
    )

    $listeners = [System.Collections.Generic.List[object]]::new()
    foreach ($connection in @($Connections)) {
        if ($null -eq $connection) { continue }

        [int]$port = 0
        if (-not [int]::TryParse([string]$connection.LocalPort, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
            continue
        }

        $localAddress = ([string]$connection.LocalAddress).Trim()
        if ([string]::IsNullOrWhiteSpace($localAddress)) { continue }

        $processName = $null
        [int]$processId = 0
        $ownership = [pscustomobject][ordered]@{
            parent_process_name = $null
            parent_process_path_available = $false
            service_name = $null
            service_state = $null
            service_start_mode = $null
            service_executable_name = $null
            service_executable_path_available = $false
        }
        if ([int]::TryParse([string]$connection.OwningProcess, [ref]$processId) -and $processId -gt 0) {
            try {
                $process = Get-Process -Id $processId -ErrorAction Stop | Select-Object -First 1
                if ($null -ne $process -and -not [string]::IsNullOrWhiteSpace([string]$process.ProcessName)) {
                    $processName = [string]$process.ProcessName
                }
            }
            catch {
                # Process ownership is useful local evidence, but access failure
                # must remain unknown rather than changing listener presence.
            }
            $ownership = Get-McNetworkOwnershipDiagnostic -ProcessId $processId
        }

        [void]$listeners.Add([pscustomobject][ordered]@{
                port          = $port
                local_address = $localAddress
                address_scope = if ($localAddress -in @('127.0.0.1', '::1')) { 'loopback' } else { 'local-machine' }
                process_name  = $processName
                parent_process_name = $ownership.parent_process_name
                parent_process_path_available = $ownership.parent_process_path_available
                service_name = $ownership.service_name
                service_state = $ownership.service_state
                service_start_mode = $ownership.service_start_mode
                service_executable_name = $ownership.service_executable_name
                service_executable_path_available = $ownership.service_executable_path_available
            })
    }

    return @($listeners | Sort-Object port,address_scope,local_address,process_name -Unique)
}

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
    $connections = @()
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

    $local = [pscustomobject][ordered]@{
        listener_processes = @(Get-McNetworkListenerDiagnostics -Connections $connections)
    }

    $wsl = [ordered]@{}
    $verificationEvents = [System.Collections.Generic.List[object]]::new()
    $wslHealth = 'success'
    $wslProbe = Invoke-McProbe -Executable 'wsl.exe' -Arguments @('--status') -Provider 'network-local-services' -ProbeName 'wsl-status' -TimeoutMs 8000 -OutputCapBytes 16384
    if ($wslProbe.status -eq 'success') {
        $wsl.present = $true
        $wsl.verification = 'verified-present'
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
        else {
            $wsl.list_verification = 'unverified'
            $wsl.list_status = [string]$listProbe.status
            $wslHealth = 'partial'
            [void]$warnings.Add("wsl distro list probe: $($listProbe.status)")
        }
    }
    else {
        $wsl.verification = 'unverified'
        $wsl.status = [string]$wslProbe.status
        $wslHealth = 'partial'
        [void]$warnings.Add("wsl status probe: $($wslProbe.status)")
        [void]$verificationEvents.Add([pscustomobject][ordered]@{
                module = 'network.wsl'
                id = 'wsl'
                provider = 'network-local-services'
                verification = 'unverified'
                reason = [string]$wslProbe.status
                source_key = 'wsl-status'
            })
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
    $health = if ($wslHealth -eq 'partial') { 'partial' } else { 'success' }
    return New-McProviderPayload -Value $value -Health $health -ResultCount ($ports.Count + 1) -Warnings @($warnings) -CoverageComplete $false -Local $local -VerificationEvents @($verificationEvents)
}
