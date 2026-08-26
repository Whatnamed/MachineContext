Set-StrictMode -Version Latest

function Get-McRenderProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name,

        [AllowNull()]
        [object]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function ConvertTo-McMarkdownValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [string]$Fallback = 'unknown'
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $Fallback }
    if ($Value -is [datetime]) { return $Value.ToUniversalTime().ToString('o', [Globalization.CultureInfo]::InvariantCulture) }
    $text = ([string]$Value).Trim()
    $text = [regex]::Replace($text, '\s+', ' ')
    $text = $text.Replace('|', '\|')
    return $text
}

function Write-McUtf8Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Text
    )

    $parent = Split-Path -Parent -Path $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) { [void](New-Item -ItemType Directory -Path $parent -Force) }
    [System.IO.File]::WriteAllText($Path, ($Text.TrimEnd("`r", "`n") + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
}

function Invoke-McRender {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$ContextRoot = (Join-Path $RepoRoot 'context'),

        [string]$OutputPath = (Join-Path $RepoRoot 'CURRENT.md')
    )

    $machine = Read-McJson -Path (Join-Path $ContextRoot 'machine.json')
    $network = Read-McJson -Path (Join-Path $ContextRoot 'network.json')
    $status = Read-McJson -Path (Join-Path $ContextRoot 'status.json')
    $conventions = Read-McJson -Path (Join-Path $ContextRoot 'conventions.json')
    $development = Read-McJson -Path (Join-Path $ContextRoot 'software\development.json')
    $ai = Read-McJson -Path (Join-Path $ContextRoot 'software\ai.json')
    $projectIndex = Read-McJson -Path (Join-Path $ContextRoot 'projects\index.json')

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add('# Current Machine Context')
    [void]$lines.Add('')
    [void]$lines.Add('> GENERATED VIEW — canonical JSON under `context/` is the source of truth.')
    [void]$lines.Add('')

    [void]$lines.Add('## Verification')
    [void]$lines.Add('')
    [void]$lines.Add(('- State: {0}' -f (ConvertTo-McMarkdownValue -Value (Get-McRenderProperty -InputObject $status -Name 'state'))))
    $providerState = Get-McRenderProperty -InputObject $status -Name 'provider_state' -Default (Get-McRenderProperty -InputObject $status -Name 'state')
    [void]$lines.Add(('- Provider state: {0}' -f (ConvertTo-McMarkdownValue -Value $providerState)))
    $published = Get-McRenderProperty -InputObject $status -Name 'published_verification' -Default ([pscustomobject][ordered]@{})
    [void]$lines.Add(('- Mode: {0}' -f (ConvertTo-McMarkdownValue -Value (Get-McRenderProperty -InputObject $published -Name 'mode'))))
    [void]$lines.Add(('- Verified at: {0}' -f (ConvertTo-McMarkdownValue -Value (Get-McRenderProperty -InputObject $published -Name 'verified_at'))))
    $auditClosure = Get-McRenderProperty -InputObject $status -Name 'audit_closure' -Default ([pscustomobject][ordered]@{})
    [void]$lines.Add(('- Audit closure: {0}' -f (ConvertTo-McMarkdownValue -Value (Get-McRenderProperty -InputObject $auditClosure -Name 'state'))))
    $auditBlocking = Get-McRenderProperty -InputObject $auditClosure -Name 'blocking' -Default ([pscustomobject][ordered]@{})
    $auditCounts = 'conflicts={0}, canonical_unknowns={1}, unresolved={2}, candidate_unknowns={3}' -f `
        (Get-McRenderProperty -InputObject $auditBlocking -Name 'conflict_count' -Default 0), `
        (Get-McRenderProperty -InputObject $auditBlocking -Name 'canonical_unknown_count' -Default 0), `
        (Get-McRenderProperty -InputObject $auditBlocking -Name 'unresolved_entry_count' -Default 0), `
        (Get-McRenderProperty -InputObject $auditBlocking -Name 'local_candidate_unknown_count' -Default 0)
    [void]$lines.Add(('- Audit findings: {0}' -f $auditCounts))
    $providerSummary = @($published.provider_summary | Sort-Object provider)
    if ($providerSummary.Count -gt 0) {
        [void]$lines.Add('- Providers:')
        foreach ($provider in $providerSummary) {
            [void]$lines.Add(('  - `{0}`: {1}' -f (ConvertTo-McMarkdownValue -Value $provider.provider), (ConvertTo-McMarkdownValue -Value $provider.health)))
        }
    }

    [void]$lines.Add('')
    [void]$lines.Add('## Machine')
    [void]$lines.Add('')
    $systemSection = Get-McRenderProperty -InputObject $machine -Name 'system' -Default ([pscustomobject][ordered]@{})
    $hardwareSection = Get-McRenderProperty -InputObject $machine -Name 'hardware' -Default ([pscustomobject][ordered]@{})
    $system = Get-McRenderProperty -InputObject $systemSection -Name 'observed' -Default ([pscustomobject][ordered]@{})
    $hardware = Get-McRenderProperty -InputObject $hardwareSection -Name 'observed' -Default ([pscustomobject][ordered]@{})
    $normalizedFamily = Get-McRenderProperty -InputObject $system -Name 'normalized_family'
    $productName = if (-not [string]::IsNullOrWhiteSpace([string]$normalizedFamily)) {
        $normalizedFamily
    }
    else {
        $rawProductName = Get-McRenderProperty -InputObject $system -Name 'raw_product_name'
        if ($null -eq $rawProductName) { $rawProductName = Get-McRenderProperty -InputObject $system -Name 'product_name' }
        $rawProductName
    }
    $edition = Get-McRenderProperty -InputObject $system -Name 'edition'
    $displayVersion = Get-McRenderProperty -InputObject $system -Name 'display_version'
    $buildNumber = Get-McRenderProperty -InputObject $system -Name 'build_number'
    $architecture = Get-McRenderProperty -InputObject $system -Name 'architecture'
    if ($null -eq $architecture) { $architecture = Get-McRenderProperty -InputObject $hardware -Name 'cpu_architecture' }
    $locale = Get-McRenderProperty -InputObject $system -Name 'locale'
    $uiLanguage = Get-McRenderProperty -InputObject $system -Name 'ui_language'
    $timeZone = Get-McRenderProperty -InputObject $system -Name 'time_zone'
    $cpuModel = Get-McRenderProperty -InputObject $hardware -Name 'cpu_model'
    $memoryBytes = Get-McRenderProperty -InputObject $hardware -Name 'memory_total_bytes'
    foreach ($pair in @(
            [pscustomobject]@{ label = 'OS'; value = ((@($productName, $edition, $displayVersion) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' ') },
            [pscustomobject]@{ label = 'Build'; value = $buildNumber },
            [pscustomobject]@{ label = 'Architecture'; value = $architecture },
            [pscustomobject]@{ label = 'Locale / UI'; value = ((@($locale, $uiLanguage) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' / ') },
            [pscustomobject]@{ label = 'Time zone'; value = $timeZone },
            [pscustomobject]@{ label = 'CPU'; value = $cpuModel },
            [pscustomobject]@{ label = 'Memory'; value = if ($null -ne $memoryBytes) { ('{0:N1} GiB' -f ([double]$memoryBytes / 1GB)) } else { $null } }
        )) {
        [void]$lines.Add(('- {0}: {1}' -f $pair.label, (ConvertTo-McMarkdownValue -Value $pair.value)))
    }
    $gpus = @(Get-McRenderProperty -InputObject $hardware -Name 'gpus')
    if ($gpus.Count -gt 0) {
        [void]$lines.Add('- GPUs:')
        foreach ($gpu in $gpus) { [void]$lines.Add(('  - {0} ({1})' -f (ConvertTo-McMarkdownValue -Value $gpu.name), (ConvertTo-McMarkdownValue -Value $gpu.driver_version))) }
    }
    $storage = @(Get-McRenderProperty -InputObject $machine -Name 'storage' -Default @() | Sort-Object mount_point)
    if ($storage.Count -gt 0) {
        [void]$lines.Add('- Storage:')
        foreach ($disk in $storage) {
            $free = if ($null -ne $disk.free_bytes -and $null -ne $disk.total_bytes) { ('{0:N1}/{1:N1} GiB free/total' -f ([double]$disk.free_bytes / 1GB), ([double]$disk.total_bytes / 1GB)) } else { $null }
            [void]$lines.Add(('  - `{0}` {1} ({2})' -f (ConvertTo-McMarkdownValue -Value $disk.mount_point), (ConvertTo-McMarkdownValue -Value $disk.filesystem), (ConvertTo-McMarkdownValue -Value $free)))
        }
    }

    [void]$lines.Add('')
    [void]$lines.Add('## Development environment')
    [void]$lines.Add('')
    $developmentItems = @($development.software | Where-Object { (Get-McRenderProperty -InputObject $_.observed -Name 'present') -eq $true } | Sort-Object kind,name,id)
    if ($developmentItems.Count -eq 0) {
        [void]$lines.Add('- No verified development tools recorded yet.')
    }
    else {
        foreach ($item in $developmentItems) {
            $itemVersion = Get-McRenderProperty -InputObject $item.observed -Name 'version'
            $itemExecutable = Get-McRenderProperty -InputObject $item.observed -Name 'executable'
            [void]$lines.Add(('- **{0}** `{1}` — {2} — `{3}`' -f (ConvertTo-McMarkdownValue -Value $item.name), (ConvertTo-McMarkdownValue -Value $item.id), (ConvertTo-McMarkdownValue -Value $itemVersion), (ConvertTo-McMarkdownValue -Value $itemExecutable)))
        }
    }

    [void]$lines.Add('')
    [void]$lines.Add('## AI and agent tooling')
    [void]$lines.Add('')
    $aiItems = @($ai.software | Where-Object { (Get-McRenderProperty -InputObject $_.observed -Name 'present') -eq $true } | Sort-Object name,id)
    if ($aiItems.Count -eq 0) {
        [void]$lines.Add('- No verified AI tools recorded yet.')
    }
    else {
        foreach ($item in $aiItems) {
            $itemVersion = Get-McRenderProperty -InputObject $item.observed -Name 'version'
            $itemExecutable = Get-McRenderProperty -InputObject $item.observed -Name 'executable'
            [void]$lines.Add(('- **{0}** `{1}` — {2} — `{3}`' -f (ConvertTo-McMarkdownValue -Value $item.name), (ConvertTo-McMarkdownValue -Value $item.id), (ConvertTo-McMarkdownValue -Value $itemVersion), (ConvertTo-McMarkdownValue -Value $itemExecutable)))
        }
    }

    [void]$lines.Add('')
    [void]$lines.Add('## Network and local services')
    [void]$lines.Add('')
    $proxySection = Get-McRenderProperty -InputObject $network -Name 'proxy' -Default ([pscustomobject][ordered]@{})
    $proxy = Get-McRenderProperty -InputObject $proxySection -Name 'observed' -Default ([pscustomobject][ordered]@{})
    [void]$lines.Add(('- System proxy enabled: {0}' -f (ConvertTo-McMarkdownValue -Value (Get-McRenderProperty -InputObject $proxy -Name 'enabled'))))
    $localProxyEndpoints = @(Get-McRenderProperty -InputObject $proxy -Name 'local_endpoints' -Default @())
    if ($localProxyEndpoints.Count -gt 0) { [void]$lines.Add(('- Local proxy endpoints: {0}' -f (($localProxyEndpoints | Sort-Object) -join ', '))) }
    $ports = @(Get-McRenderProperty -InputObject $network -Name 'ports' -Default @() | Sort-Object port,address_scope -Unique)
    if ($ports.Count -gt 0) {
        [void]$lines.Add('- Observed allowlisted local listening ports:')
        foreach ($port in $ports) { [void]$lines.Add(('  - `{0}` ({1})' -f $port.port, (ConvertTo-McMarkdownValue -Value $port.address_scope))) }
    }
    $wsl = Get-McRenderProperty -InputObject $network -Name 'wsl'
    if ($null -ne $wsl -and (Get-McRenderProperty -InputObject $wsl -Name 'present') -eq $true) { [void]$lines.Add(('- WSL: present; distros: {0}' -f ((@(Get-McRenderProperty -InputObject $wsl -Name 'distros' -Default @()) | Sort-Object) -join ', '))) }

    [void]$lines.Add('')
    [void]$lines.Add('## Projects')
    [void]$lines.Add('')
    $projects = @(Get-McRenderProperty -InputObject $projectIndex -Name 'projects' -Default @() | Sort-Object name,id)
    if ($projects.Count -eq 0) {
        [void]$lines.Add('- No verified projects recorded yet.')
    }
    else {
        foreach ($project in $projects) { [void]$lines.Add(('- **{0}** — `{1}` — status: {2}' -f (ConvertTo-McMarkdownValue -Value $project.name), (ConvertTo-McMarkdownValue -Value $project.path), (ConvertTo-McMarkdownValue -Value 'see project record'))) }
    }

    [void]$lines.Add('')
    [void]$lines.Add('## Installation conventions')
    [void]$lines.Add('')
    $directories = Get-McRenderProperty -InputObject $conventions -Name 'directories' -Default ([pscustomobject][ordered]@{})
    $knownRoots = @(Get-McRenderProperty -InputObject $directories -Name 'known_roots' -Default @() | ForEach-Object { if ($_ -is [string]) { $_ } else { Get-McRenderProperty -InputObject $_ -Name 'path' } } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object)
    $knownRootsText = if ($knownRoots.Count -gt 0) { $knownRoots -join ', ' } else { 'none recorded' }
    [void]$lines.Add(('- Known roots: {0}' -f $knownRootsText))
    [void]$lines.Add('- Conventions remain bootstrap/curated until confirmed from observed machine usage.')

    $text = $lines -join [Environment]::NewLine
    Write-McUtf8Text -Path $OutputPath -Text $text
    return $OutputPath
}
