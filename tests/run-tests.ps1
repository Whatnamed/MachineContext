[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'scripts\lib\runtime.ps1')
. (Join-Path $RepoRoot 'scripts\lib\collection.ps1')
. (Join-Path $RepoRoot 'scripts\lib\reconcile.ps1')
. (Join-Path $RepoRoot 'scripts\lib\validation.ps1')

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-McTrue {
    param(
        [bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        [void]$failures.Add($Message)
    }
}

function Assert-McEqual {
    param(
        [AllowNull()][object]$Actual,
        [AllowNull()][object]$Expected,
        [Parameter(Mandatory)][string]$Message
    )

    if ([string]$Actual -ne [string]$Expected) {
        [void]$failures.Add("$Message (actual='$Actual', expected='$Expected')")
    }
}

function Invoke-McTest {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )

    try {
        & $Body
        if ($failures.Count -eq 0 -or $failures[$failures.Count - 1] -notlike "${Name}:*") {
            Write-Host "PASS $Name"
        }
    }
    catch {
        [void]$failures.Add("$($Name): $($_.Exception.Message)")
        Write-Host "FAIL $Name"
    }
}

Invoke-McTest -Name 'deterministic JSON ordering and UTF-8' -Body {
    $object = [ordered]@{
        z = 1
        id = 'fixture'
        observed = [ordered]@{ b = 2; a = 1 }
    }
    $first = ConvertTo-McJsonText -InputObject $object
    $second = ConvertTo-McJsonText -InputObject $object
    Assert-McEqual -Actual $first -Expected $second -Message 'JSON serialization must repeat byte-for-byte'
    Assert-McTrue -Condition ($first.IndexOf('"id"') -lt $first.IndexOf('"z"')) -Message 'stable key order must put id before z'
    Assert-McTrue -Condition ($first -match '"observed"\s*:\s*\{') -Message 'nested objects must remain objects'
    $timestamp = [datetime]::SpecifyKind([datetime]::Parse('2026-08-25T18:48:08.2169236'), [datetimekind]::Utc)
    $timestampJson = ConvertTo-McJsonText -InputObject ([pscustomobject][ordered]@{ verified_at = $timestamp })
    Assert-McTrue -Condition ($timestampJson -match '2026-08-25T18:48:08\.2169236Z') -Message 'DateTime values must serialize as invariant ISO timestamps'
    $emptyArray = Copy-McJsonObject -InputObject @()
    Assert-McEqual -Actual $emptyArray.Count -Expected 0 -Message 'empty arrays must survive JSON round-trip'
    $singleArray = Copy-McJsonObject -InputObject @('one')
    Assert-McEqual -Actual $singleArray.Count -Expected 1 -Message 'single-item arrays must not collapse to scalars'

    $path = Join-Path $RepoRoot '.local\test-json.json'
    Write-McJson -Path $path -InputObject $object
    $roundTrip = Read-McJson -Path $path
    Assert-McEqual -Actual $roundTrip.observed.a -Expected 1 -Message 'JSON round-trip should preserve nested values'
    $bytes = [System.IO.File]::ReadAllBytes($path)
    Assert-McTrue -Condition (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) -Message 'JSON must be UTF-8 without BOM'
    Remove-Item -LiteralPath $path -Force
}

Invoke-McTest -Name 'recursive JSON type contract' -Body {
    $emptyArray = Copy-McValue -InputObject @()
    $singleArray = Copy-McValue -InputObject @('one')
    $multiArray = Copy-McValue -InputObject @('one', 'two')
    Assert-McTrue -Condition ((Test-McSequence -InputObject $emptyArray) -and $emptyArray -is [System.Array]) -Message 'empty arrays must remain arrays'
    Assert-McTrue -Condition ((Test-McSequence -InputObject $singleArray) -and @($singleArray).Count -eq 1 -and $singleArray -is [System.Array]) -Message 'single arrays must remain arrays'
    Assert-McTrue -Condition ((Test-McSequence -InputObject $multiArray) -and @($multiArray).Count -eq 2 -and $multiArray -is [System.Array]) -Message 'multi-item arrays must remain arrays'

    $ordered = [ordered]@{ first = 1; second = @('a', 'b') }
    $custom = [pscustomobject][ordered]@{ first = 1; nested = [pscustomobject][ordered]@{ values = @() } }
    $orderedCopy = Copy-McValue -InputObject $ordered
    $customCopy = Copy-McValue -InputObject $custom
    Assert-McTrue -Condition (Test-McMapping -InputObject $orderedCopy) -Message 'ordered dictionaries must remain mappings'
    Assert-McTrue -Condition (Test-McMapping -InputObject $customCopy) -Message 'PSCustomObject values must remain mappings'
    Assert-McTrue -Condition (Test-McSequence -InputObject $orderedCopy.second) -Message 'mapping arrays must remain sequences'
    Assert-McTrue -Condition (Test-McSequence -InputObject $customCopy.nested.values) -Message 'nested empty arrays must remain sequences'

    $legacyMetadata = [pscustomobject][ordered]@{
        Count = 1
        IsFixedSize = $true
        IsReadOnly = $false
        IsSynchronized = $false
        Length = 1
        LongLength = 1
        Rank = 1
        SyncRoot = [pscustomobject][ordered]@{ id = 'legacy-item' }
    }
    $repairedLegacy = Copy-McValue -InputObject $legacyMetadata
    Assert-McTrue -Condition (Test-McSequence -InputObject $repairedLegacy) -Message 'legacy collection metadata must repair to a sequence'
    Assert-McEqual -Actual $repairedLegacy[0].id -Expected 'legacy-item' -Message 'legacy collection metadata must retain SyncRoot items'

    $morphoProject = [pscustomobject][ordered]@{
        schema_version = 1
        id = 'project-morpho-fixture'
        name = 'Morpho-like project'
        observed = [pscustomobject][ordered]@{
            local_path = '%USERPROFILE%\\src\\Morpho'
            repository = 'github.com/Whatnamed/Morpho'
            runtime_refs = @('node', 'python')
            package_manager_refs = @('npm')
            tool_refs = @()
            service_refs = @([pscustomobject][ordered]@{ id = 'local-service'; port = 3000 })
            manifests = @([pscustomobject][ordered]@{ kind = 'package-manifest'; path = '%USERPROFILE%\\src\\Morpho\\package.json' })
            commands = [pscustomobject][ordered]@{ build = 'npm run build'; test = 'npm test' }
            local_endpoints = @()
            evidence = @([pscustomobject][ordered]@{ type = 'fixture' })
        }
        curated = [pscustomobject][ordered]@{ status = 'active'; constraints = @('preserve-recovery') }
    }
    $software = [pscustomobject][ordered]@{
        schema_version = 1
        id = 'fixture-tool'
        kind = 'runtime'
        name = 'Fixture Tool'
        observed = [pscustomobject][ordered]@{
            present = $true
            version = '1.0.0'
            executable = '%USERPROFILE%\\bin\\fixture.exe'
            command_resolution = @([pscustomobject][ordered]@{ executable = '%USERPROFILE%\\bin\\fixture.exe'; command_type = 'PersistentApplication' })
            install = [pscustomobject][ordered]@{ root = '%USERPROFILE%\\bin' }
            evidence = @([pscustomobject][ordered]@{ provider = 'fixture'; fields = @('version') })
        }
        curated = [pscustomobject][ordered]@{ status = 'unknown'; constraints = @() }
    }
    $fixtureText = ConvertTo-McJsonText -InputObject ([pscustomobject][ordered]@{ project = $morphoProject; software = $software })
    Assert-McTrue -Condition ($fixtureText -notmatch 'SyncRoot|IsFixedSize|IsReadOnly|LongLength|Rank') -Message 'recursive serializer must not emit .NET collection metadata'

    $fixtureJsonPath = Join-Path $RepoRoot '.local\test-contract-roundtrip.json'
    try {
        Write-McJson -Path $fixtureJsonPath -InputObject ([pscustomobject][ordered]@{ project = $morphoProject; software = $software })
        $roundTrip = Read-McJson -Path $fixtureJsonPath
        Assert-McTrue -Condition (Test-McSequence -InputObject $roundTrip.project.observed.runtime_refs) -Message 'project runtime_refs must round-trip as a sequence'
        Assert-McTrue -Condition (Test-McMapping -InputObject $roundTrip.project.observed.commands) -Message 'project commands must round-trip as a mapping'
        Assert-McTrue -Condition (Test-McSequence -InputObject $roundTrip.software.observed.command_resolution) -Message 'software command_resolution must round-trip as a sequence'
    }
    finally {
        if (Test-Path -LiteralPath $fixtureJsonPath -PathType Leaf) { Remove-Item -LiteralPath $fixtureJsonPath -Force }
    }
}

Invoke-McTest -Name 'persistent host environment scope' -Body {
    $fixtureRoot = Join-Path $RepoRoot '.local\test-environment'
    $persistentRoot = Join-Path $fixtureRoot 'persistent\Git\Git\cmd'
    $persistentOther = Join-Path $fixtureRoot 'persistent-other'
    $processRoot = Join-Path $fixtureRoot 'collector-process-override'
    $persistentPath = Join-Path $persistentRoot 'git.exe'
    $persistentExe = Join-Path $persistentRoot 'tool.exe'
    $persistentCmd = Join-Path $persistentRoot 'tool.cmd'
    $processGit = Join-Path $processRoot 'git.exe'
    New-Item -ItemType Directory -Path $persistentRoot, $persistentOther, $processRoot -Force | Out-Null
    New-Item -ItemType File -Path $persistentPath, $persistentExe, $persistentCmd, $processGit -Force | Out-Null

    try {
        $machinePath = '{0};{1}' -f $persistentRoot, $persistentOther
        $userOnlyRoot = Join-Path $fixtureRoot 'persistent-user-only'
        $userPath = '{0};{1}' -f $persistentRoot, $userOnlyRoot
        $entries = @(Get-McPersistentPathEntries -MachinePathValue $machinePath -UserPathValue $userPath)
        $hostEnvironment = Get-McPersistentEnvironment -MachinePathValue $machinePath -UserPathValue $userPath
        $hostGit = @(Resolve-McPersistentCommand -Executable 'git' -PathEntries $entries)
        $hostTool = @(Resolve-McPersistentCommand -Executable 'tool' -PathEntries $entries)
        Assert-McEqual -Actual $hostEnvironment.scope -Expected 'windows-host' -Message 'persistent environment must be windows-host scoped'
        Assert-McEqual -Actual $hostGit[0].path -Expected (ConvertTo-McNormalizedPath -Path $persistentPath -ResolveExisting) -Message 'host resolution must use persistent Git path'
        Assert-McEqual -Actual $hostGit[0].source -Expected 'persistent-path' -Message 'host resolution must identify persistent-path source'
        Assert-McEqual -Actual ([System.IO.Path]::GetExtension([string]$hostTool[0].path).ToLowerInvariant()) -Expected '.exe' -Message 'persistent command resolution must prefer .exe'
        Assert-McEqual -Actual @($hostEnvironment.machine_path).Count -Expected 2 -Message 'machine path order/deduplication must be preserved'
        Assert-McEqual -Actual @($hostEnvironment.user_path).Count -Expected 2 -Message 'user path order/deduplication must be preserved'
        Assert-McEqual -Actual @($hostEnvironment.persistent_effective_path).Count -Expected 3 -Message 'effective persistent path must deduplicate across scopes'

        $previousPath = $env:Path
        try {
            $env:Path = '{0};{1}' -f $processRoot, $persistentRoot
            $processGitCandidates = @(Get-McProcessExecutableCandidates -Executable 'git.exe')
            Assert-McEqual -Actual $processGitCandidates[0].path -Expected $processGit -Message 'collector-process resolution must observe process PATH pollution'
            $hostAgain = @(Resolve-McPersistentCommand -Executable 'git' -PathEntries $entries)
            Assert-McEqual -Actual $hostAgain[0].path -Expected (ConvertTo-McNormalizedPath -Path $persistentPath -ResolveExisting) -Message 'host resolution must ignore process PATH pollution'
        }
        finally {
            $env:Path = $previousPath
        }
    }
    finally {
        if (Test-Path -LiteralPath $fixtureRoot -PathType Container) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    }
}

Invoke-McTest -Name 'canonical contract fixture validation' -Body {
    $fixtureRoot = Join-Path $RepoRoot '.local\test-contract'
    $contextRoot = Join-Path $fixtureRoot 'context'
    New-Item -ItemType Directory -Path (Join-Path $contextRoot 'software'), (Join-Path $contextRoot 'projects') -Force | Out-Null
    $softwareRecord = [pscustomobject][ordered]@{
        schema_version = 1
        id = 'fixture-runtime'
        kind = 'runtime'
        name = 'Fixture Runtime'
        observed = [pscustomobject][ordered]@{
            present = $true
            version = '1.0.0'
            executable = '%USERPROFILE%\\bin\\fixture.exe'
            command_resolution = @([pscustomobject][ordered]@{ executable = '%USERPROFILE%\\bin\\fixture.exe'; command_type = 'PersistentApplication' })
            install = [pscustomobject][ordered]@{ root = '%USERPROFILE%\\bin' }
            evidence = @()
        }
        curated = [pscustomobject][ordered]@{ status = 'unknown'; constraints = @() }
    }
    $projectRecord = [pscustomobject][ordered]@{
        schema_version = 1
        id = 'fixture-project'
        name = 'Fixture Project'
        observed = [pscustomobject][ordered]@{
            local_path = '%USERPROFILE%\\src\\fixture'
            repository = $null
            runtime_refs = @('fixture-runtime')
            package_manager_refs = @('npm')
            tool_refs = @()
            service_refs = @()
            manifests = @([pscustomobject][ordered]@{ kind = 'package-manifest'; path = '%USERPROFILE%\\src\\fixture\\package.json' })
            commands = [pscustomobject][ordered]@{ test = 'npm test' }
            local_endpoints = @()
            evidence = @([pscustomobject][ordered]@{ type = 'fixture' })
        }
        curated = [pscustomobject][ordered]@{ status = 'active'; constraints = @() }
    }
    $machineRecord = [pscustomobject][ordered]@{
        schema_version = 1
        system = [pscustomobject][ordered]@{ observed = [pscustomobject][ordered]@{}; curated = [pscustomobject][ordered]@{} }
        hardware = [pscustomobject][ordered]@{ observed = [pscustomobject][ordered]@{}; curated = [pscustomobject][ordered]@{} }
        paths = [pscustomobject][ordered]@{ scope = 'windows-host'; machine_path = @(); user_path = @(); persistent_effective_path = @(); entry_count = 0; known_roots = @() }
        environment = [pscustomobject][ordered]@{ scope = 'windows-host'; path_summary = @(); shell_profiles = @() }
        storage = @()
        shells = @()
        command_resolution = @()
        constraints = @()
    }
    $manifest = [pscustomobject][ordered]@{
        schema_version = 1
        canonical = [pscustomobject][ordered]@{
            status = 'context/status.json'
            machine = 'context/machine.json'
            network = 'context/network.json'
            conventions = 'context/conventions.json'
            relationships = 'context/relationships.json'
            software_index = 'context/software/index.json'
            software_development = 'context/software/development.json'
            software_ai = 'context/software/ai.json'
            projects_index = 'context/projects/index.json'
        }
    }
    $documents = @{
        'machine-context.json' = $manifest
        'context/status.json' = [pscustomobject][ordered]@{ schema_version = 1; state = 'partial' }
        'context/machine.json' = $machineRecord
        'context/network.json' = [pscustomobject][ordered]@{ schema_version = 1 }
        'context/conventions.json' = [pscustomobject][ordered]@{ schema_version = 1 }
        'context/relationships.json' = [pscustomobject][ordered]@{ schema_version = 1; relationships = @() }
        'context/software/index.json' = [pscustomobject][ordered]@{ schema_version = 1; modules = @() }
        'context/software/development.json' = [pscustomobject][ordered]@{ schema_version = 1; software = @($softwareRecord) }
        'context/software/ai.json' = [pscustomobject][ordered]@{ schema_version = 1; software = @() }
        'context/projects/index.json' = [pscustomobject][ordered]@{ schema_version = 1; projects = @([pscustomobject][ordered]@{ id = 'fixture-project'; name = 'Fixture Project'; path = '%USERPROFILE%\\src\\fixture'; context_file = 'context/projects/fixture-project.json' }) }
        'context/projects/fixture-project.json' = $projectRecord
    }
    foreach ($relative in $documents.Keys) {
        Write-McJson -Path (Join-Path $fixtureRoot $relative) -InputObject $documents[$relative]
    }
    $currentPath = Join-Path $fixtureRoot 'CURRENT.md'
    [System.IO.File]::WriteAllText($currentPath, "> GENERATED VIEW`r`n`r`nfixture`r`n", [System.Text.UTF8Encoding]::new($false))

    try {
        $valid = Invoke-McValidation -RepoRoot $fixtureRoot -ContextRoot $contextRoot -CurrentPath $currentPath
        Assert-McTrue -Condition $valid.ok -Message 'fresh canonical fixture must pass validation'

        $badProject = Copy-McJsonObject -InputObject $projectRecord
        $badProject.observed.runtime_refs = [pscustomobject][ordered]@{ SyncRoot = @() }
        Write-McJson -Path (Join-Path $fixtureRoot 'context/projects/fixture-project.json') -InputObject $badProject
        $invalid = Invoke-McValidation -RepoRoot $fixtureRoot -ContextRoot $contextRoot -CurrentPath $currentPath
        Assert-McTrue -Condition (@($invalid.errors | Where-Object code -eq 'dotnet_collection_metadata').Count -gt 0) -Message 'validator must reject .NET collection metadata'
    }
    finally {
        if (Test-Path -LiteralPath $fixtureRoot -PathType Container) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    }
}

Invoke-McTest -Name 'path and URL normalization' -Body {
    $userProfile = [Environment]::GetEnvironmentVariable('USERPROFILE')
    Assert-McTrue -Condition (-not [string]::IsNullOrWhiteSpace($userProfile)) -Message 'USERPROFILE must be available for path fixture'
    $normalized = ConvertTo-McNormalizedPath -Path (Join-Path $userProfile '中文\工具\')
    Assert-McEqual -Actual $normalized -Expected '%USERPROFILE%\中文\工具' -Message 'user path should be normalized without account name'
    $repository = ConvertTo-McSafeRepositoryIdentity -Remote 'https://user:password@github.com/Whatnamed/MachineContext.git?token=secret'
    Assert-McEqual -Actual $repository -Expected 'github.com/Whatnamed/MachineContext' -Message 'remote identity must remove credentials/query and .git'
    Assert-McTrue -Condition (Test-McSafeId -Id 'runtime-node.js') -Message 'stable IDs should accept safe generated IDs'
}

Invoke-McTest -Name 'dedicated verifiers and verification states' -Body {
    Assert-McEqual -Actual (Get-McWindowsNormalizedFamily -ProductName 'Windows 10 Home' -BuildNumber '26200') -Expected 'Windows 11' -Message 'Windows build must determine normalized family'
    Assert-McEqual -Actual (Get-McWindowsNormalizedFamily -ProductName 'Windows 10 Pro' -BuildNumber '19045') -Expected 'Windows 10' -Message 'Windows 10 build must remain Windows 10'

    $nvidia = @(ConvertFrom-McNvidiaSmiText -Text "NVIDIA Fixture, 555.12, 8192`r`n")
    Assert-McEqual -Actual $nvidia[0].vram_bytes -Expected ([int64](8192MB)) -Message 'nvidia-smi memory must convert MiB to bytes'
    Assert-McEqual -Actual $nvidia[0].vram_source -Expected 'nvidia-smi' -Message 'nvidia VRAM source must be explicit'

    $hardwareVerifierPath = Join-Path $RepoRoot 'scripts\collectors\hardware-verifiers.ps1'
    $unavailableNvidia = & {
        param($Path)
        function Get-McHostToolCandidates {
            param(
                [string]$Command,
                [string[]]$KnownPaths
            )
            return @()
        }
        . $Path
        Get-McNvidiaSmiObservation
    } $hardwareVerifierPath
    Assert-McEqual -Actual $unavailableNvidia.health -Expected 'unavailable' -Message 'missing optional nvidia-smi must fail soft'
    Assert-McEqual -Actual $unavailableNvidia.value.check.status -Expected 'unavailable' -Message 'missing nvidia-smi check must remain diagnostic'

    $vswhere = @(ConvertFrom-McVsWhereJson -Text '[{"installationPath":"D:\\Visual Studio\\product","installationVersion":"17.1","displayName":"Fixture VS","isComplete":true}]')
    Assert-McEqual -Actual $vswhere[0].installation_path -Expected 'D:\Visual Studio\product' -Message 'vswhere installation path must be normalized'
    Assert-McEqual -Actual $vswhere[0].is_complete -Expected $true -Message 'vswhere completion flag must survive parsing'

    $sdks = @(ConvertFrom-McDotnetSdkText -Text "8.0.400 [C:\Program Files\dotnet\sdk]`r`n")
    $runtimes = @(ConvertFrom-McDotnetRuntimeText -Text "Microsoft.NETCore.App 8.0.10 [C:\Program Files\dotnet\shared\Microsoft.NETCore.App]`r`n")
    Assert-McEqual -Actual $sdks[0].version -Expected '8.0.400' -Message 'dotnet SDK version must parse'
    Assert-McEqual -Actual $runtimes[0].name -Expected 'Microsoft.NETCore.App' -Message 'dotnet runtime name must parse'

    $shellPayload = Get-McShellObservation
    $gitBash = @($shellPayload.value.shells | Where-Object id -eq 'shell-git-bash')
    Assert-McTrue -Condition ($gitBash.Count -le 1) -Message 'Git Bash must have at most one authoritative record'
    if ($gitBash.Count -eq 1) {
        Assert-McTrue -Condition ([string]$gitBash[0].observed.executable -notmatch '(?i)WindowsApps\\bash\.exe') -Message 'WindowsApps bash alias must not be published as Git Bash'
    }

    $baseModule = [pscustomobject][ordered]@{
        schema_version = 1
        meta = [pscustomobject][ordered]@{ state = 'observed' }
        software = @([pscustomobject][ordered]@{
                id = 'fixture-tool'
                kind = 'runtime'
                name = 'Fixture Tool'
                observed = [pscustomobject][ordered]@{ present = $true; verification = 'verified-present'; version = '1.0.0' }
                curated = [pscustomobject][ordered]@{ status = 'active' }
            })
    }
    $unverified = Merge-McSoftwareModule -Module $baseModule -ModuleName development -Observations @() -VerificationEvents @([pscustomobject][ordered]@{ module = 'development'; id = 'fixture-tool'; provider = 'fixture'; verification = 'unverified'; reason = 'timed_out' })
    Assert-McEqual -Actual $unverified.software[0].observed.present -Expected $true -Message 'unverified verification must preserve present state'
    Assert-McEqual -Actual $unverified.software[0].observed.verification -Expected 'unverified' -Message 'timeout must mark known entity unverified'
    Assert-McEqual -Actual $unverified.software[0].observed.version -Expected '1.0.0' -Message 'timeout must preserve old observed fields'
    Assert-McEqual -Actual $unverified.software[0].curated.status -Expected 'active' -Message 'verification state must not overwrite curated meaning'

    $unsafeUnverifiedObservation = [pscustomobject][ordered]@{
        id = 'fixture-tool'
        kind = 'runtime'
        name = 'Fixture Tool'
        observed = [pscustomobject][ordered]@{ present = $false; verification = 'unverified'; reason = 'probe-failed' }
    }
    $safeUnverified = Merge-McSoftwareModule -Module $baseModule -ModuleName development -Observations @($unsafeUnverifiedObservation)
    Assert-McEqual -Actual $safeUnverified.software[0].observed.present -Expected $true -Message 'unverified false must not erase a previously present entity'
    Assert-McEqual -Actual $safeUnverified.software[0].observed.verification -Expected 'unverified' -Message 'unverified observation state must be retained'

    $absentModule = [pscustomobject][ordered]@{
        schema_version = 1
        meta = [pscustomobject][ordered]@{ state = 'observed' }
        software = @([pscustomobject][ordered]@{
                id = 'fixture-tool'
                kind = 'runtime'
                name = 'Fixture Tool'
                observed = [pscustomobject][ordered]@{ present = $true; verification = 'verified-present'; version = '1.0.0' }
                curated = [pscustomobject][ordered]@{ status = 'active' }
            })
    }
    $absent = Merge-McSoftwareModule -Module $absentModule -ModuleName development -Observations @() -VerificationEvents @([pscustomobject][ordered]@{ module = 'development'; id = 'fixture-tool'; provider = 'fixture'; verification = 'verified-absent'; reason = 'direct-check' })
    Assert-McEqual -Actual $absent.software[0].observed.present -Expected $false -Message 'high-confidence absence must retain record with present false'
    Assert-McEqual -Actual $absent.software[0].observed.verification -Expected 'verified-absent' -Message 'high-confidence absence state'
    Assert-McEqual -Actual $absent.software[0].observed.last_known.present -Expected $true -Message 'absence must retain last known observed state'
    Assert-McEqual -Actual $absent.software[0].curated.status -Expected 'active' -Message 'absence must preserve curated meaning'
}

Invoke-McTest -Name 'project root classification and promotion' -Body {
    $fixtureRoot = Join-Path $RepoRoot '.local\test-project-policy'
    $projectPath = Join-Path $fixtureRoot 'Projects\fixture-app'
    $sdkPath = Join-Path $fixtureRoot 'Dev\flutter'
    $cachePath = Join-Path $fixtureRoot 'Dev\npm-cache\_npx\fixture'
    New-Item -ItemType Directory -Path $projectPath, $sdkPath, $cachePath -Force | Out-Null

    $projectPolicy = [pscustomobject][ordered]@{ root = (Join-Path $fixtureRoot 'Projects'); kind = 'project-root'; source = 'fixture-project-root'; auto_promote = $true; walk_depth = 5; priority = 60 }
    $sdkPolicy = [pscustomobject][ordered]@{ root = (Join-Path $fixtureRoot 'Dev\flutter'); kind = 'sdk-root'; source = 'fixture-sdk-root'; auto_promote = $false; walk_depth = 0; priority = 90 }
    $cachePolicy = [pscustomobject][ordered]@{ root = (Join-Path $fixtureRoot 'Dev\npm-cache'); kind = 'cache-root'; source = 'fixture-cache-root'; auto_promote = $false; walk_depth = 0; priority = 100 }
    $policies = @($projectPolicy, $sdkPolicy, $cachePolicy)

    try {
        New-Item -ItemType File -Path (Join-Path $projectPath '.git') -Force | Out-Null
        Write-McJson -Path (Join-Path $projectPath 'package.json') -InputObject ([pscustomobject][ordered]@{
                name = '@fixture/manifest-name'
                packageManager = 'pnpm@9.1.0'
                scripts = [pscustomobject][ordered]@{ test = 'pnpm test' }
            })
        New-Item -ItemType File -Path (Join-Path $sdkPath '.git') -Force | Out-Null
        Write-McJson -Path (Join-Path $sdkPath 'package.json') -InputObject ([pscustomobject][ordered]@{ name = 'sdk-package' })
        Write-McJson -Path (Join-Path $cachePath 'package.json') -InputObject ([pscustomobject][ordered]@{ name = 'cached-package' })

        $projectCandidate = Get-McProjectCandidateAtPath -Path $projectPath -RootPolicy $projectPolicy -RootPolicies $policies
        $sdkCandidate = Get-McProjectCandidateAtPath -Path $sdkPath -RootPolicy $sdkPolicy -RootPolicies $policies
        $cacheCandidate = Get-McProjectCandidateAtPath -Path $cachePath -RootPolicy $cachePolicy -RootPolicies $policies

        Assert-McEqual -Actual $projectCandidate.name_hint -Expected '@fixture/manifest-name' -Message 'manifest name should be used without a remote repository'
        Assert-McEqual -Actual $projectCandidate.name_source -Expected 'manifest' -Message 'manifest name source should be explicit'
        Assert-McEqual -Actual $projectCandidate.observed.package_manager -Expected 'pnpm@9.1.0' -Message 'packageManager should take precedence over lockfile inference'
        Assert-McTrue -Condition ($projectCandidate.verified -and $projectCandidate.promotion_eligible) -Message 'Git fingerprint under project root should be promotion eligible'
        Assert-McEqual -Actual $sdkCandidate.classification -Expected 'sdk-root' -Message 'SDK root classification should be retained'
        Assert-McTrue -Condition (-not $sdkCandidate.promotion_eligible) -Message 'SDK Git repositories must remain local candidates'
        Assert-McTrue -Condition (-not $cacheCandidate.verified -and -not $cacheCandidate.promotion_eligible) -Message 'cache manifest candidates must not be verified or promoted'

        $remoteName = Get-McProjectNameHint -Repository 'github.com/Whatnamed/RemoteProject' -PackageName '@fixture/manifest-name' -DirectoryName 'app'
        Assert-McEqual -Actual $remoteName.value -Expected 'RemoteProject' -Message 'repository basename should outrank manifest name'
        Assert-McEqual -Actual $remoteName.source -Expected 'repository' -Message 'repository name source should be explicit'

        $segmentPolicy = Get-McProjectRootPolicyForPath -Path (Join-Path $projectPath 'node_modules\package') -Policies $policies
        Assert-McEqual -Actual $segmentPolicy.kind -Expected 'cache-root' -Message 'generated dependency paths must be non-promotable'
    }
    finally {
        if (Test-Path -LiteralPath $fixtureRoot -PathType Container) { Remove-Item -LiteralPath $fixtureRoot -Recurse -Force }
    }
}

Invoke-McTest -Name 'bounded discovery remains candidate-only' -Body {
    $toolPattern = Get-McDiscoveryToolPatternMatch -FileName 'node.exe'
    Assert-McEqual -Actual $toolPattern.name -Expected 'node' -Message 'bounded discovery must recognize high-value tool fingerprints'
    Assert-McTrue -Condition ($null -eq (Get-McDiscoveryToolPatternMatch -FileName 'random-library.dll')) -Message 'bounded discovery must ignore unrelated binaries'

    $policy = [pscustomobject][ordered]@{ root = 'E:\Portable'; kind = 'unknown-root'; source = 'fixture'; auto_promote = $false; walk_depth = 1; priority = 0 }
    $everythingPattern = [pscustomobject][ordered]@{ query = 'node.exe'; kind = 'portable-tool'; name = 'node' }
    $candidate = New-McEverythingCandidate -RawPath 'E:\Portable\node.exe' -Pattern $everythingPattern -Policy $policy
    Assert-McEqual -Actual $candidate.source -Expected 'everything-index' -Message 'Everything result must retain its source'
    Assert-McTrue -Condition (-not $candidate.verified -and -not $candidate.promotion_eligible) -Message 'indexed filesystem hits must never be directly promoted'
    Assert-McEqual -Actual $candidate.classification -Expected 'unknown-root' -Message 'indexed candidate must retain root classification'

    $gitPattern = [pscustomobject][ordered]@{ query = '*.git'; kind = 'project-or-tool'; name = $null }
    $gitCandidate = New-McEverythingCandidate -RawPath 'E:\Portable\repo\.git' -Pattern $gitPattern -Policy $policy
    Assert-McEqual -Actual $gitCandidate.path -Expected 'E:\Portable\repo' -Message 'Everything Git fingerprint must point at its parent candidate root'
    Assert-McTrue -Condition (-not $gitCandidate.promotion_eligible) -Message 'Everything Git fingerprints must still require verification'
}

Invoke-McTest -Name 'privacy guardrails' -Body {
    Assert-McTrue -Condition (-not (Test-McPrivacySafeText -Text 'https://user:secret@example.test/repo')) -Message 'credential-bearing URL must be rejected'
    Assert-McTrue -Condition (-not (Test-McPrivacySafeText -Text 'api_key=not-for-commit')) -Message 'credential assignment must be rejected'
    Assert-McTrue -Condition (Test-McPrivacySafeText -Text '%USERPROFILE%\\.codex\\auth.json exists') -Message 'safe auth-file existence hint should be allowed'
}

Invoke-McTest -Name 'safe subprocess probe' -Body {
    $success = Invoke-McProbe -Executable 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-Command', 'Write-Output probe-ok') -Provider 'fixture' -ProbeName 'success' -TimeoutMs 5000 -ResolutionScope 'collector-process'
    Assert-McEqual -Actual $success.status -Expected 'success' -Message 'successful probe health'
    Assert-McEqual -Actual $success.exit_code -Expected 0 -Message 'successful probe exit code'
    Assert-McTrue -Condition ($success.stdout -match 'probe-ok') -Message 'probe stdout must be captured'

    $stderr = Invoke-McProbe -Executable 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-Command', "[Console]::Error.WriteLine('version-on-stderr')") -Provider 'fixture' -ProbeName 'stderr' -TimeoutMs 5000 -ResolutionScope 'collector-process'
    Assert-McEqual -Actual $stderr.status -Expected 'success' -Message 'stderr-only successful probe health'
    Assert-McTrue -Condition ($stderr.stderr -match 'version-on-stderr') -Message 'probe stderr must be captured'
    Assert-McEqual -Actual (Get-McProbeVersionText -Probe $stderr) -Expected 'version-on-stderr' -Message 'version parser must accept stderr'

    $missing = Invoke-McProbe -Executable 'mc-command-that-cannot-exist-9f3a2d.exe' -Arguments @('--version') -Provider 'fixture' -ProbeName 'missing' -TimeoutMs 5000 -ResolutionScope 'collector-process'
    Assert-McEqual -Actual $missing.status -Expected 'unavailable' -Message 'missing command must fail soft'

    $timeout = Invoke-McProbe -Executable 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-Command', 'Start-Sleep -Seconds 5') -Provider 'fixture' -ProbeName 'timeout' -TimeoutMs 250 -ResolutionScope 'collector-process'
    Assert-McEqual -Actual $timeout.status -Expected 'timed_out' -Message 'probe timeout status'
    Assert-McTrue -Condition $timeout.timed_out -Message 'timeout flag must be set'

    $capped = Invoke-McProbe -Executable 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-Command', "Write-Output ('x' * 10000)") -Provider 'fixture' -ProbeName 'cap' -TimeoutMs 5000 -OutputCapBytes 1024 -ResolutionScope 'collector-process'
    Assert-McEqual -Actual $capped.status -Expected 'success' -Message 'capped probe health'
    Assert-McTrue -Condition $capped.output_truncated -Message 'probe output cap must be reported'
}

Invoke-McTest -Name 'curated ownership and safe absence semantics' -Body {
    $module = [pscustomobject][ordered]@{
        schema_version = 1
        meta = [pscustomobject][ordered]@{ state = 'observed' }
        software = @([pscustomobject][ordered]@{
            id = 'node'
            kind = 'runtime'
            name = 'Node.js'
            observed = [pscustomobject][ordered]@{ present = $true; version = 'old' }
            curated = [pscustomobject][ordered]@{ status = 'active'; role = 'primary' }
        })
    }
    $unchanged = Merge-McSoftwareModule -Module $module -Observations @()
    Assert-McEqual -Actual @($unchanged.software).Count -Expected 1 -Message 'provider failure/empty observations must not remove known entities'
    Assert-McEqual -Actual $unchanged.software[0].curated.status -Expected 'active' -Message 'curated status must survive an empty provider result'

    $observation = [pscustomobject][ordered]@{
        id = 'node'
        kind = 'runtime'
        name = 'Node.js'
        observed = [pscustomobject][ordered]@{ present = $true; version = 'new' }
    }
    $updated = Merge-McSoftwareModule -Module $module -Observations @($observation)
    Assert-McEqual -Actual $updated.software[0].observed.version -Expected 'new' -Message 'observed fields should update from a verified observation'
    Assert-McEqual -Actual $updated.software[0].curated.role -Expected 'primary' -Message 'collector must not overwrite curated role'
}

Invoke-McTest -Name 'provider diagnostics and local state' -Body {
    $diagnostics = New-McDiagnosticsContext -Mode Quick
    [void](Add-McProviderDiagnostic -Diagnostics $diagnostics -Provider 'fixture-success' -Health success -DurationMs 4.2 -ResultCount 2 -CoverageComplete $true)
    [void](Add-McProviderDiagnostic -Diagnostics $diagnostics -Provider 'fixture-optional' -Health unavailable -Optional $true)
    [void](Add-McProviderDiagnostic -Diagnostics $diagnostics -Provider 'fixture-optional-timeout' -Health timed_out -Optional $true)
    Assert-McEqual -Actual (Get-McOverallProviderHealth -Providers $diagnostics.providers) -Expected 'success' -Message 'optional unavailable provider should not make the whole scan partial'

    $diagnostics.overall_health = 'success'
    $status = [pscustomobject][ordered]@{
        schema_version = 1
        state = 'verified'
        published_verification = [pscustomobject][ordered]@{
            mode = 'Quick'
            verified_at = [datetime]::Parse('2026-08-25T18:48:08.2169236Z').ToUniversalTime()
            provider_summary = ConvertTo-McPublishedProviderSummary -Providers $diagnostics.providers
        }
    }
    $status = Update-McPublishedStatus -Status $status -Diagnostics $diagnostics -Mode 'Quick'
    Assert-McTrue -Condition ([string]$status.published_verification.verified_at -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$') -Message 'published verification timestamps must remain invariant ISO'

    $testLocalRoot = Join-Path $RepoRoot '.local\test-runtime'
    $run = New-McRunContext -RepoRoot $RepoRoot -Mode Quick -LocalRoot $testLocalRoot
    try {
        Write-McLocalRunArtifacts -RunContext $run -Observations ([pscustomobject]@{ schema_version = 1; software = @() }) -Candidates ([pscustomobject]@{ schema_version = 1; candidates = @() }) -Diagnostics $diagnostics
        Write-McLocalState -RunContext $run -Diagnostics $diagnostics
        Assert-McTrue -Condition (Test-Path -LiteralPath $run.diagnostics_path -PathType Leaf) -Message 'diagnostics artifact must be written under .local'
        Assert-McTrue -Condition (Test-Path -LiteralPath $run.local_diagnostics_path -PathType Leaf) -Message 'local diagnostics artifact must be written under .local'
        Assert-McTrue -Condition (Test-Path -LiteralPath $run.state_path -PathType Leaf) -Message 'local state must be written under .local'
    }
    finally {
        if (Test-Path -LiteralPath $run.local_root -PathType Container) {
            Remove-Item -LiteralPath $run.local_root -Recurse -Force
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host "FAILED $($failures.Count) assertion(s)"
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host 'All MachineContext tests passed.'
