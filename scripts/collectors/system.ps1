Set-StrictMode -Version Latest

function Get-McOptionalProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory)]
        [string]$Name
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-McRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Name
    )

    try {
        $item = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
        return Get-McOptionalProperty -InputObject $item -Name $Name
    }
    catch {
        return $null
    }
}

function ConvertTo-McStableFreeBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int64]$Bytes
    )

    # Free space is useful for placement planning, but exact bytes create
    # semantic noise while the scan itself is running. A 256 MiB bucket keeps
    # meaningful capacity changes while making ordinary churn byte-stable.
    $bucket = [int64](256MB)
    return [int64]([math]::Floor($Bytes / $bucket) * $bucket)
}

function Get-McSystemHardwareObservation {
    [CmdletBinding()]
    param()

    $warnings = [System.Collections.Generic.List[string]]::new()
    $system = [ordered]@{}
    $hardware = [ordered]@{}
    $storage = [System.Collections.Generic.List[object]]::new()
    $constraints = [System.Collections.Generic.List[object]]::new()
    $resultCount = 0

    $os = $null
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $resultCount++
    }
    catch {
        [void]$warnings.Add('Win32_OperatingSystem unavailable')
    }

    $computer = $null
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $resultCount++
    }
    catch {
        [void]$warnings.Add('Win32_ComputerSystem unavailable')
    }

    $processor = $null
    try {
        $processor = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $resultCount++
    }
    catch {
        [void]$warnings.Add('Win32_Processor unavailable')
    }

    $memoryModules = @()
    try {
        $memoryModules = @(Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction Stop)
        $resultCount++
    }
    catch {
        [void]$warnings.Add('Win32_PhysicalMemory unavailable')
    }

    $gpus = @()
    try {
        $gpus = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction Stop)
        $resultCount++
    }
    catch {
        [void]$warnings.Add('Win32_VideoController unavailable')
    }

    $disks = @()
    try {
        $disks = @(Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop)
        $resultCount++
    }
    catch {
        [void]$warnings.Add('Win32_LogicalDisk unavailable')
    }

    $currentVersion = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $productName = Get-McRegistryValue -Path $currentVersion -Name 'ProductName'
    $edition = Get-McRegistryValue -Path $currentVersion -Name 'EditionID'
    $displayVersion = Get-McRegistryValue -Path $currentVersion -Name 'DisplayVersion'
    $build = Get-McRegistryValue -Path $currentVersion -Name 'CurrentBuild'
    $ubr = Get-McRegistryValue -Path $currentVersion -Name 'UBR'

    if ($null -ne $productName) {
        $system.raw_product_name = [string]$productName
        $system.normalized_family = Get-McWindowsNormalizedFamily -ProductName ([string]$productName) -BuildNumber ([string]$build)
    }
    if ($null -ne $edition) { $system.edition = [string]$edition }
    if ($null -ne $displayVersion) { $system.display_version = [string]$displayVersion }
    if ($null -ne $build) { $system.build_number = [string]$build }
    if ($null -ne $ubr) { $system.update_build_revision = [int]$ubr }
    if ($null -ne $os) {
        $architecture = Get-McOptionalProperty -InputObject $os -Name 'OSArchitecture'
        if ($null -ne $architecture) { $system.architecture = [string]$architecture }
        $locale = Get-McOptionalProperty -InputObject $os -Name 'Locale'
        if ($null -ne $locale) { $system.locale_id = [string]$locale }
    }

    try {
        $system.locale = (Get-Culture).Name
        $system.ui_language = (Get-UICulture).Name
        $system.time_zone = [TimeZoneInfo]::Local.Id
    }
    catch {
        [void]$warnings.Add('locale or timezone query unavailable')
    }

    $system.machine_context_root = ConvertTo-McNormalizedPath -Path (Join-Path $PSScriptRoot '..\..') -ResolveExisting
    $system.scope = 'windows-host'

    $processorName = Get-McOptionalProperty -InputObject $processor -Name 'Name'
    if ($null -ne $processorName) { $hardware.cpu_model = ([string]$processorName).Trim() }
    $logical = Get-McOptionalProperty -InputObject $processor -Name 'NumberOfLogicalProcessors'
    if ($null -ne $logical) { $hardware.logical_cores = [int]$logical }
    $physical = Get-McOptionalProperty -InputObject $processor -Name 'NumberOfCores'
    if ($null -ne $physical) { $hardware.physical_cores = [int]$physical }
    if ($null -ne $processor) {
        $cpuArchitecture = Get-McOptionalProperty -InputObject $processor -Name 'Architecture'
        $hardware.cpu_architecture = switch ([int]$cpuArchitecture) {
            0 { 'x86' }
            5 { 'arm' }
            6 { 'ia64' }
            9 { 'x64' }
            12 { 'arm64' }
            default { [string]$cpuArchitecture }
        }
    }

    $memoryBytes = 0L
    foreach ($module in @($memoryModules)) {
        $capacity = Get-McOptionalProperty -InputObject $module -Name 'Capacity'
        if ($null -ne $capacity) {
            $memoryBytes += [int64]$capacity
        }
    }
    if ($memoryBytes -gt 0) { $hardware.memory_total_bytes = $memoryBytes }

    $gpuRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($gpu in @($gpus)) {
        $name = Get-McOptionalProperty -InputObject $gpu -Name 'Name'
        if ([string]::IsNullOrWhiteSpace([string]$name)) { continue }
        $record = [ordered]@{ name = ([string]$name).Trim() }
        $driver = Get-McOptionalProperty -InputObject $gpu -Name 'DriverVersion'
        if ($null -ne $driver) { $record.driver_version = [string]$driver }
        $record.vram_status = 'unknown'
        $record.vram_source = if ([string]$name -match '(?i)nvidia') { 'nvidia-smi-required' } else { 'dedicated-verifier-required' }
        [void]$gpuRecords.Add([pscustomobject]$record)
    }
    if ($gpuRecords.Count -gt 0) { $hardware.gpus = $gpuRecords }

    foreach ($disk in @($disks)) {
        $device = Get-McOptionalProperty -InputObject $disk -Name 'DeviceID'
        $size = Get-McOptionalProperty -InputObject $disk -Name 'Size'
        $free = Get-McOptionalProperty -InputObject $disk -Name 'FreeSpace'
        if ([string]::IsNullOrWhiteSpace([string]$device)) { continue }
        $record = [ordered]@{
            mount_point = ([string]$device).TrimEnd('\') + '\'
        }
        $fileSystem = Get-McOptionalProperty -InputObject $disk -Name 'FileSystem'
        if ($null -ne $fileSystem) { $record.filesystem = [string]$fileSystem }
        if ($null -ne $size) { $record.total_bytes = [int64]$size }
        if ($null -ne $free) { $record.free_bytes = ConvertTo-McStableFreeBytes -Bytes ([int64]$free) }
        [void]$storage.Add([pscustomobject]$record)
    }

    $developerMode = Get-McRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense'
    if ($null -ne $developerMode) {
        [void]$constraints.Add([pscustomobject][ordered]@{ name = 'developer_mode'; observed = ([int]$developerMode -eq 1) })
    }
    $longPaths = Get-McRegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled'
    if ($null -ne $longPaths) {
        [void]$constraints.Add([pscustomobject][ordered]@{ name = 'long_paths_enabled'; observed = ([int]$longPaths -eq 1) })
    }
    $hypervisor = Get-McOptionalProperty -InputObject $computer -Name 'HypervisorPresent'
    if ($null -ne $hypervisor) {
        [void]$constraints.Add([pscustomobject][ordered]@{ name = 'hypervisor_present'; observed = [bool]$hypervisor })
    }

    $value = [pscustomobject][ordered]@{
        system      = [pscustomobject]$system
        hardware    = [pscustomobject]$hardware
        storage     = @($storage)
        constraints = @($constraints)
    }
    $health = if ($warnings.Count -gt 0 -and $resultCount -gt 0) { 'partial' } elseif ($resultCount -eq 0) { 'failed' } else { 'success' }
    return New-McProviderPayload -Value $value -Health $health -ResultCount $resultCount -Warnings @($warnings) -CoverageComplete ($health -eq 'success')
}
