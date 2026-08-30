[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'scripts\lib\runtime.ps1')
. (Join-Path $RepoRoot 'scripts\lib\collection.ps1')
. (Join-Path $RepoRoot 'scripts\lib\reconcile.ps1')
. (Join-Path $RepoRoot 'scripts\lib\audit.ps1')
. (Join-Path $RepoRoot 'scripts\lib\review.ps1')
. (Join-Path $RepoRoot 'scripts\lib\validation.ps1')
. (Join-Path $RepoRoot 'scripts\lib\curation.ps1')
. (Join-Path $RepoRoot 'scripts\lib\rendering.ps1')
. (Join-Path $RepoRoot 'scripts\collectors\visual-studio.ps1')

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

Invoke-McTest -Name 'deterministic reconciliation ordering for JSON dictionaries' -Body {
    $module = [pscustomobject][ordered]@{
        schema_version = 1
        id = 'development'
        software = @(
            [ordered]@{ schema_version = 1; id = 'dotnet'; kind = 'runtime'; name = '.NET' },
            [ordered]@{ schema_version = 1; id = 'cargo'; kind = 'package-manager'; name = 'Cargo' },
            [ordered]@{ schema_version = 1; id = 'bun'; kind = 'runtime'; name = 'Bun' }
        )
        meta = [ordered]@{ state = 'observed' }
    }
    $merged = Merge-McSoftwareModule -Module $module -ModuleName development -Observations @() -VerificationEvents @()
    $ids = @($merged.software | ForEach-Object { [string]$_.id })
    Assert-McEqual -Actual ($ids -join ',') -Expected 'bun,cargo,dotnet' -Message 'software records read as dictionaries must sort by id'
}

Invoke-McTest -Name 'legacy Codex identity migrates to split CLI record' -Body {
    $module = [pscustomobject][ordered]@{
        schema_version = 1
        id = 'ai'
        software = @([pscustomobject][ordered]@{
                schema_version = 1
                id = 'codex'
                kind = 'ai-tool'
                name = 'Codex'
                observed = [pscustomobject][ordered]@{
                    present = $true
                    verification = 'verified-present'
                    config_paths = @([pscustomobject][ordered]@{
                            path = '%USERPROFILE%\\.codex\\auth.json'
                            exists = $true
                            kind = 'auth-file'
                        })
                }
                curated = [pscustomobject][ordered]@{ status = 'unknown'; role = 'primary' }
            })
        meta = [pscustomobject][ordered]@{ state = 'observed' }
    }
    $observation = [pscustomobject][ordered]@{
        schema_version = 1
        id = 'codex-cli'
        kind = 'ai-tool'
        name = 'Codex CLI'
        observed = [pscustomobject][ordered]@{
            present = $true
            verification = 'verified-present'
            version = '0.149.1'
        }
    }
    $merged = Merge-McSoftwareModule -Module $module -ModuleName ai -Observations @($observation)
    $ids = @($merged.software | ForEach-Object { [string]$_.id })
    Assert-McEqual -Actual ($ids -join ',') -Expected 'codex-cli' -Message 'legacy Codex id must not remain after split migration'
    $codexCli = @($merged.software | Where-Object id -eq 'codex-cli')[0]
    Assert-McEqual -Actual $codexCli.observed.version -Expected '0.149.1' -Message 'split Codex CLI observation must win for current facts'
    Assert-McEqual -Actual $codexCli.observed.config_paths[0].path -Expected '%USERPROFILE%\\.codex\\auth.json' -Message 'legacy Codex evidence must be retained'
    Assert-McEqual -Actual $codexCli.curated.role -Expected 'primary' -Message 'legacy Codex curated intent must be retained'
}

Invoke-McTest -Name 'CURRENT rendering falls back to verified install locations' -Body {
    $visualStudioObserved = [pscustomobject][ordered]@{
        version = '17.13.35919.96'
        install = [pscustomobject][ordered]@{
            root = 'D:\\Visual Studio\\product'
            installations = @([pscustomobject][ordered]@{ installation_path = 'D:\\Visual Studio\\product' })
        }
    }
    $desktopObserved = [pscustomobject][ordered]@{ install_location = '%LOCALAPPDATA%\\Packages\\OpenAI.Codex\\Install' }
    Assert-McEqual -Actual (Get-McRenderLocation -Observed $visualStudioObserved) -Expected 'D:\\Visual Studio\\product' -Message 'renderer should use verified install root when executable is absent'
    Assert-McEqual -Actual (Get-McRenderLocation -Observed $desktopObserved) -Expected '%LOCALAPPDATA%\\Packages\\OpenAI.Codex\\Install' -Message 'renderer should use verified package install location'
}

Invoke-McTest -Name 'Visual Studio Native Desktop workload preserves verification states' -Body {
    $present = ConvertTo-McVisualStudioDesktopCppObservation -ProbeStatus 'success' -ProbeText '[{"installationPath":"D:\\Visual Studio\\product"}]'
    $absent = ConvertTo-McVisualStudioDesktopCppObservation -ProbeStatus 'success' -ProbeText '[]'
    $failed = ConvertTo-McVisualStudioDesktopCppObservation -ProbeStatus 'timed_out' -ProbeText ''
    Assert-McEqual -Actual $present.verification -Expected 'verified-present' -Message 'Native Desktop workload should be present when vswhere returns an installation'
    Assert-McEqual -Actual $present.installation_paths[0] -Expected 'D:\Visual Studio\product' -Message 'workload installation paths must be normalized'
    Assert-McEqual -Actual $absent.verification -Expected 'verified-absent' -Message 'successful empty workload query should be verified-absent'
    Assert-McEqual -Actual $absent.present -Expected $false -Message 'verified-absent workload must expose present=false'
    Assert-McEqual -Actual $failed.verification -Expected 'unverified' -Message 'workload timeout must remain unverified'
    Assert-McTrue -Condition ($null -eq $failed.PSObject.Properties['present']) -Message 'unverified workload must not expose an absent claim'
}

Invoke-McTest -Name 'Visual Studio workload type contract rejects unsafe states' -Body {
    $valid = [pscustomobject][ordered]@{
        schema_version = 1
        id = 'visual-studio'
        kind = 'ide'
        name = 'Visual Studio'
        observed = [pscustomobject][ordered]@{
            present = $true
            verification = 'verified-present'
            desktop_cpp_workload = [pscustomobject][ordered]@{
                workload_id = 'Microsoft.VisualStudio.Workload.NativeDesktop'
                verification = 'verified-present'
                present = $true
                installation_paths = @('D:\Visual Studio\product')
            }
        }
        curated = [pscustomobject][ordered]@{ status = 'unknown' }
    }
    $validFindings = [System.Collections.Generic.List[object]]::new()
    Validate-McSoftwareRecord -Record $valid -Findings $validFindings -Path '$.software[0]'
    Assert-McEqual -Actual $validFindings.Count -Expected 0 -Message 'valid Visual Studio workload should pass the type contract'

    $unverified = Copy-McJsonObject -InputObject $valid
    $unverified.observed.desktop_cpp_workload = ConvertTo-McVisualStudioDesktopCppObservation -ProbeStatus 'timed_out' -ProbeText ''
    $unverifiedFindings = [System.Collections.Generic.List[object]]::new()
    Validate-McSoftwareRecord -Record $unverified -Findings $unverifiedFindings -Path '$.software[0]'
    Assert-McEqual -Actual $unverifiedFindings.Count -Expected 0 -Message 'unverified workload may omit paths without becoming a validation failure'
    $unsafeUnverified = Copy-McJsonObject -InputObject $unverified
    $unsafeUnverified.observed.desktop_cpp_workload.present = $false
    $unsafeUnverifiedFindings = [System.Collections.Generic.List[object]]::new()
    Validate-McSoftwareRecord -Record $unsafeUnverified -Findings $unsafeUnverifiedFindings -Path '$.software[0]'
    Assert-McTrue -Condition (@($unsafeUnverifiedFindings | Where-Object code -eq 'visual_studio_workload_unsafe_absence').Count -eq 1) -Message 'unverified workload must reject present=false'

    $invalid = Copy-McJsonObject -InputObject $valid
    $invalid.observed.desktop_cpp_workload.verification = 'verified-present'
    $invalid.observed.desktop_cpp_workload.present = $false
    $invalid.observed.desktop_cpp_workload.installation_paths = @()
    $invalidFindings = [System.Collections.Generic.List[object]]::new()
    Validate-McSoftwareRecord -Record $invalid -Findings $invalidFindings -Path '$.software[0]'
    Assert-McTrue -Condition (@($invalidFindings | Where-Object code -eq 'visual_studio_workload_present_contract').Count -eq 1) -Message 'unsafe verified-present workload must be rejected'
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

Invoke-McTest -Name 'semantic version and banner normalization' -Body {
    Assert-McEqual -Actual (ConvertTo-McSemanticVersion -Text 'pip 25.0.1 from C:\Users\hasee\.agent-reach-venv\Lib\site-packages\pip (python 3.12)') -Expected '25.0.1' -Message 'pip banners must become semantic versions without paths'
    Assert-McEqual -Actual (ConvertTo-McSemanticVersion -Text 'git version 2.53.0.windows.3') -Expected '2.53.0' -Message 'Git banners must discard provider suffixes'
    Assert-McEqual -Actual (ConvertTo-McSemanticVersion -Text 'Flutter 3.41.9 • channel stable • https://github.com/flutter/flutter.git') -Expected '3.41.9' -Message 'Flutter banners must become semantic versions'
    Assert-McEqual -Actual (ConvertTo-McSemanticVersion -Text 'go version go1.24.11 windows/amd64') -Expected '1.24.11' -Message 'Go banners must strip the go prefix'
    Assert-McEqual -Actual (ConvertTo-McSemanticVersion -Text 'not a version banner with C:\Users\hasee\secret') -Expected $null -Message 'unparseable banners must not enter canonical version fields'

    $rawEntity = [pscustomobject][ordered]@{
        id = 'pip'
        kind = 'package-manager'
        name = 'pip'
        observed = [pscustomobject][ordered]@{
            present = $true
            version = 'pip 25.0.1 from C:\Users\hasee\.agent-reach-venv\Lib\site-packages\pip (python 3.12)'
        }
    }
    $normalizedEntity = ConvertTo-McNormalizedEntityVersion -Entity $rawEntity
    Assert-McEqual -Actual $normalizedEntity.observed.version -Expected '25.0.1' -Message 'entity normalization must publish only parsed version'
    Assert-McTrue -Condition ([string]$normalizedEntity.observed.version -notmatch 'Users|agent-reach-venv|site-packages') -Message 'canonical version must not contain the user path from a banner'

    $machine = [pscustomobject][ordered]@{
        shells = @([pscustomobject][ordered]@{
                id = 'shell-fixture'
                kind = 'shell'
                name = 'Fixture shell'
                observed = [pscustomobject][ordered]@{ version = 'GNU bash, version 5.2.21(1)-release (x86_64-pc-msys)' }
            })
    }
    Merge-McMachineShells -Machine $machine -Current @()
    Assert-McEqual -Actual $machine.shells[0].observed.version -Expected '5.2.21' -Message 'historical shell banners must be normalized during reconciliation'
}

Invoke-McTest -Name 'package-manager local evidence stays non-authoritative' -Body {
    $fixtureRoot = Join-Path $RepoRoot '.local\test-pnpm-evidence'
    $localAppData = Join-Path $fixtureRoot 'LocalAppData'
    $appData = Join-Path $fixtureRoot 'AppData'
    $userProfile = Join-Path $fixtureRoot 'UserProfile'
    try {
        [void](New-Item -ItemType Directory -Path (Join-Path $localAppData 'pnpm\store') -Force)
        Write-McJson -Path (Join-Path $localAppData 'pnpm\pnpm.cmd') -InputObject ([ordered]@{ fixture = $true })
        $evidence = Get-McRuntimeLocalDiagnostics -LocalAppDataPath $localAppData -AppDataPath $appData -UserProfilePath $userProfile -PersistentPathEntries @()
        $pnpm = $evidence.package_managers.pnpm
        Assert-McTrue -Condition $pnpm.store_present -Message 'pnpm store presence should be retained as local evidence'
        Assert-McTrue -Condition $pnpm.store_is_not_cli_proof -Message 'pnpm store evidence must explicitly remain non-authoritative'
        $localCmd = @($pnpm.known_path_checks | Where-Object id -eq 'local-pnpm-cmd' | Select-Object -First 1)
        Assert-McEqual -Actual $localCmd.present -Expected $true -Message 'allowlisted pnpm executable path check should detect the fixture file'
        Assert-McEqual -Actual @($pnpm.persistent_candidates).Count -Expected 0 -Message 'fixture persistent PATH should not invent a pnpm command'
    }
    finally {
        if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
        }
    }
}

Invoke-McTest -Name 'collector process paths never become canonical host facts' -Body {
    Assert-McTrue -Condition (Test-McCollectorProcessOnlyPath -Path '%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd') -Message 'Codex runtime paths must be recognized as process-only'
    Assert-McTrue -Condition (-not (Test-McCollectorProcessOnlyPath -Path 'D:\Node.js\Node.js\npm.cmd')) -Message 'persistent host tool paths must remain eligible'

    $module = [pscustomobject][ordered]@{
        schema_version = 1
        meta = [pscustomobject][ordered]@{ state = 'observed' }
        software = @([pscustomobject][ordered]@{
                id = 'pnpm'
                kind = 'package-manager'
                name = 'pnpm'
                observed = [pscustomobject][ordered]@{
                    present = $true
                    verification = 'unverified'
                    version = '11.19.0'
                    executable = '%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd'
                    install = @([pscustomobject][ordered]@{ root = '%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback' })
                    command_resolution = @([pscustomobject][ordered]@{ executable = '%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\bin\fallback\pnpm.cmd' })
                    evidence = @([pscustomobject][ordered]@{ provider = 'command' })
                }
                curated = [pscustomobject][ordered]@{ status = 'unknown' }
            })
    }
    $cleaned = Merge-McSoftwareModule -Module $module -ModuleName development -Observations @() -VerificationEvents @([pscustomobject][ordered]@{
            module = 'development'
            id = 'pnpm'
            provider = 'runtimes-package-managers-toolchain'
            verification = 'unverified'
            reason = 'persistent-command-not-found'
    })
    $observed = $cleaned.software[0].observed
    Assert-McTrue -Condition (($null -eq (Get-McObjectPropertyOrNull -InputObject $observed -Name 'present')) -and ($null -eq (Get-McObjectPropertyOrNull -InputObject $observed -Name 'version')) -and ($null -eq (Get-McObjectPropertyOrNull -InputObject $observed -Name 'executable'))) -Message 'process-only facts must be removed instead of published as host facts'
    Assert-McEqual -Actual (Get-McObjectPropertyOrNull -InputObject $observed -Name 'verification') -Expected 'unverified' -Message 'process-only cleanup must retain unknown verification state'
    Assert-McTrue -Condition ((ConvertTo-McJsonText -InputObject $cleaned) -notmatch 'codex-runtimes|pnpm\.cmd') -Message 'process-only path must not remain anywhere in the canonical entity'
}

Invoke-McTest -Name 'strong relationship derivation' -Body {
    $software = [pscustomobject][ordered]@{
        development = @(
            [pscustomobject][ordered]@{ id = 'node'; observed = [pscustomobject][ordered]@{ present = $true; verification = 'verified-present'; executable = 'E:\Node\node.exe'; install = [pscustomobject][ordered]@{ root = 'E:\Node' } } },
            [pscustomobject][ordered]@{ id = 'npm'; observed = [pscustomobject][ordered]@{ present = $true; verification = 'verified-present'; executable = 'E:\Node\npm.cmd' } },
            [pscustomobject][ordered]@{ id = 'flutter'; observed = [pscustomobject][ordered]@{ present = $true; verification = 'verified-present'; executable = 'E:\Flutter\bin\flutter.bat'; install = [pscustomobject][ordered]@{ root = 'E:\Flutter\bin' } } },
            [pscustomobject][ordered]@{ id = 'dart'; observed = [pscustomobject][ordered]@{ present = $true; verification = 'verified-present'; executable = 'E:\Flutter\bin\dart.bat' } },
            [pscustomobject][ordered]@{ id = 'git'; observed = [pscustomobject][ordered]@{ present = $true; verification = 'verified-present'; executable = 'D:\Git\Git\cmd\git.exe'; install = [pscustomobject][ordered]@{ root = 'D:\Git\Git' } } }
        )
        ai = @()
    }
    $observations = [pscustomobject][ordered]@{
        software = $software
        machine = [pscustomobject][ordered]@{
            shells = @([pscustomobject][ordered]@{
                    id = 'shell-git-bash'
                    observed = [pscustomobject][ordered]@{
                        present = $true
                        verification = 'verified-present'
                        git_root = 'D:\Git\Git'
                        git_executable = 'D:\Git\Git\cmd\git.exe'
                    }
                })
        }
        projects = @(
            [pscustomobject][ordered]@{
                id = 'project-fixture'
                verified = $true
                promotion_eligible = $true
                observed = [pscustomobject][ordered]@{
                    runtime_refs = @('node')
                    package_manager_refs = @('npm')
                    manifests = @([pscustomobject][ordered]@{ path = 'E:\Projects\fixture\package.json' })
                }
            },
            [pscustomobject][ordered]@{
                id = 'project-sdk-fixture'
                verified = $true
                promotion_eligible = $false
                observed = [pscustomobject][ordered]@{ runtime_refs = @('node'); package_manager_refs = @(); manifests = @() }
            }
        )
    }
    $relationships = @(Get-McStrongRelationships -Observations $observations)
    Assert-McTrue -Condition (@($relationships | Where-Object { $_.from -eq 'npm' -and $_.relation -eq 'provided_by' -and $_.to -eq 'node' }).Count -eq 1) -Message 'Node-local npm should have a strong provided_by relationship'
    Assert-McTrue -Condition (@($relationships | Where-Object { $_.from -eq 'dart' -and $_.relation -eq 'provided_by' -and $_.to -eq 'flutter' }).Count -eq 1) -Message 'Flutter-bundled Dart should have a strong provided_by relationship'
    Assert-McTrue -Condition (@($relationships | Where-Object { $_.from -eq 'shell-git-bash' -and $_.relation -eq 'provided_by' -and $_.to -eq 'git' -and $_.origin -eq 'detected' }).Count -eq 1) -Message 'Git Bash should be related to the verified Git installation'
    Assert-McTrue -Condition (@($relationships | Where-Object { $_.from -eq 'project-fixture' -and $_.relation -eq 'uses_runtime' -and $_.to -eq 'node' }).Count -eq 1) -Message 'promotable projects may reference observed runtimes'
    Assert-McTrue -Condition (@($relationships | Where-Object { $_.from -eq 'project-fixture' -and $_.relation -eq 'uses_package_manager' -and $_.to -eq 'npm' }).Count -eq 1) -Message 'promotable projects may reference observed package managers'
    Assert-McTrue -Condition (@($relationships | Where-Object { $_.from -eq 'project-sdk-fixture' }).Count -eq 0) -Message 'non-promotable candidates must not create canonical relationships'
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

    $timedOutNvidia = & {
        param($Path)
        function Get-McHostToolCandidates {
            param(
                [string]$Command,
                [string[]]$KnownPaths
            )
            return @([pscustomobject][ordered]@{ path = 'C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe' })
        }
        function Invoke-McProbe {
            param(
                [string]$Executable,
                [object[]]$Arguments,
                [string]$Provider,
                [string]$ProbeName,
                [int]$TimeoutMs,
                [int]$OutputCapBytes,
                [string]$ResolutionScope
            )
            return [pscustomobject][ordered]@{ status = 'timed_out'; stdout = '' }
        }
        . $Path
        Get-McNvidiaSmiObservation
    } $hardwareVerifierPath
    Assert-McEqual -Actual $timedOutNvidia.health -Expected 'timed_out' -Message 'nvidia-smi probe timeout must fail soft with an explicit health'
    Assert-McEqual -Actual $timedOutNvidia.value.check.status -Expected 'timed_out' -Message 'nvidia-smi probe timeout must surface the probe status in check'
    Assert-McTrue -Condition (@($timedOutNvidia.value.candidates).Count -eq 1) -Message 'nvidia-smi probe timeout must retain the executable candidate for later promotion'

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

    $hostToolPayload = Get-McHostAuthoritativeToolObservation
    $supabaseHostEntity = @($hostToolPayload.value.development_entities | Where-Object id -eq 'supabase')
    if ($supabaseHostEntity.Count -eq 1) {
        Assert-McTrue -Condition ([string]$supabaseHostEntity[0].observed.executable -notmatch '(?i)SupabaseCLI\\2\.109\.1') -Message 'Supabase verifier must not resolve to stale rollback directory 2.109.1'
        Assert-McTrue -Condition (@($supabaseHostEntity[0].observed.command_resolution | Where-Object { [string]$_.executable -match '(?i)SupabaseCLI\\2\.109\.1' }).Count -eq 0) -Message 'Supabase command resolution must not retain stale rollback directory'
        Assert-McEqual -Actual $supabaseHostEntity[0].observed.command_resolution[0].source -Expected 'persistent-path' -Message 'Supabase must resolve strictly via persistent host command resolution'
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

    $nestedBase = [pscustomobject][ordered]@{
        schema_version = 1
        meta = [pscustomobject][ordered]@{ state = 'observed' }
        software = @([pscustomobject][ordered]@{
                id = 'visual-studio'
                kind = 'ide'
                name = 'Visual Studio'
                observed = [pscustomobject][ordered]@{
                    present = $true
                    verification = 'verified-present'
                    desktop_cpp_workload = [pscustomobject][ordered]@{
                        workload_id = 'Microsoft.VisualStudio.Workload.NativeDesktop'
                        present = $true
                        verification = 'verified-present'
                        installation_paths = @('D:\Visual Studio\product')
                        probe_status = 'success'
                    }
                }
                curated = [pscustomobject][ordered]@{ status = 'active' }
            })
    }
    $nestedTimeoutObservation = [pscustomobject][ordered]@{
        id = 'visual-studio'
        kind = 'ide'
        name = 'Visual Studio'
        observed = [pscustomobject][ordered]@{
            desktop_cpp_workload = [pscustomobject][ordered]@{
                workload_id = 'Microsoft.VisualStudio.Workload.NativeDesktop'
                verification = 'unverified'
                probe_status = 'timed_out'
            }
        }
    }
    $nestedTimeout = Merge-McSoftwareModule -Module (Copy-McJsonObject -InputObject $nestedBase) -ModuleName development -Observations @($nestedTimeoutObservation)
    $nestedTimeoutWorkload = @($nestedTimeout.software | Where-Object id -eq 'visual-studio')[0].observed.desktop_cpp_workload
    Assert-McEqual -Actual $nestedTimeoutWorkload.present -Expected $true -Message 'nested verifier timeout must preserve prior presence'
    Assert-McEqual -Actual $nestedTimeoutWorkload.verification -Expected 'unverified' -Message 'nested verifier timeout must mark the workload unverified'
    Assert-McEqual -Actual $nestedTimeoutWorkload.installation_paths[0] -Expected 'D:\Visual Studio\product' -Message 'nested verifier timeout must preserve prior installation paths'
    Assert-McEqual -Actual $nestedTimeoutWorkload.probe_status -Expected 'timed_out' -Message 'nested verifier timeout must retain current probe status'

    $nestedAbsentObservation = [pscustomobject][ordered]@{
        id = 'visual-studio'
        kind = 'ide'
        name = 'Visual Studio'
        observed = [pscustomobject][ordered]@{
            desktop_cpp_workload = [pscustomobject][ordered]@{
                workload_id = 'Microsoft.VisualStudio.Workload.NativeDesktop'
                present = $false
                verification = 'verified-absent'
                installation_paths = @()
                probe_status = 'success'
            }
        }
    }
    $nestedAbsent = Merge-McSoftwareModule -Module (Copy-McJsonObject -InputObject $nestedBase) -ModuleName development -Observations @($nestedAbsentObservation)
    $nestedAbsentWorkload = @($nestedAbsent.software | Where-Object id -eq 'visual-studio')[0].observed.desktop_cpp_workload
    Assert-McEqual -Actual $nestedAbsentWorkload.present -Expected $false -Message 'nested verified absence must expose present=false'
    Assert-McEqual -Actual $nestedAbsentWorkload.verification -Expected 'verified-absent' -Message 'nested verified absence state'
    Assert-McEqual -Actual $nestedAbsentWorkload.last_known.present -Expected $true -Message 'nested verified absence must retain last known presence'
    Assert-McEqual -Actual $nestedAbsentWorkload.last_known.installation_paths[0] -Expected 'D:\Visual Studio\product' -Message 'nested verified absence must retain last known paths'
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

Invoke-McTest -Name 'historical project demotion preserves curated intent' -Body {
    $fixtureRoot = Join-Path $RepoRoot '.local\test-project-migration\.cache'
    $contextRoot = Join-Path $fixtureRoot 'context'
    $projectRoot = Join-Path $contextRoot 'projects'
    New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
    $removedFiles = [System.Collections.Generic.List[string]]::new()
    $demoted = [System.Collections.Generic.List[object]]::new()
    $index = [pscustomobject][ordered]@{ schema_version = 1; projects = @(); project_policy = [pscustomobject][ordered]@{} }
    try {
        $sdkRecord = [pscustomobject][ordered]@{
            schema_version = 1
            id = 'project-historical-sdk'
            name = 'sdk'
            observed = [pscustomobject][ordered]@{ local_path = (Join-Path $fixtureRoot 'Dev\flutter') }
            curated = [pscustomobject][ordered]@{ status = 'unknown' }
        }
        $curatedRecord = [pscustomobject][ordered]@{
            schema_version = 1
            id = 'project-curated-sdk'
            name = 'curated-sdk'
            observed = [pscustomobject][ordered]@{ local_path = (Join-Path $fixtureRoot 'Dev\tool') }
            curated = [pscustomobject][ordered]@{ status = 'active' }
        }
        Write-McJson -Path (Join-Path $projectRoot 'project-historical-sdk.json') -InputObject $sdkRecord
        Write-McJson -Path (Join-Path $projectRoot 'project-curated-sdk.json') -InputObject $curatedRecord
        $merged = Merge-McProjects -ContextRoot $contextRoot -ProjectIndex $index -Candidates @() -RemovedFiles $removedFiles -DemotedProjects $demoted
        Assert-McEqual -Actual @($merged.projects).Count -Expected 1 -Message 'only the explicitly curated historical record should remain'
        Assert-McEqual -Actual $merged.projects[0].id -Expected 'project-curated-sdk' -Message 'curated project must survive non-project root migration'
        Assert-McEqual -Actual $demoted[0].id -Expected 'project-historical-sdk' -Message 'un-curated SDK record should be reported as demoted'
        Assert-McEqual -Actual $demoted[0].classification -Expected 'cache-root' -Message 'fixture under ignored local state should use conservative cache classification'
        Assert-McTrue -Condition ($removedFiles -contains 'context/projects/project-historical-sdk.json') -Message 'demotion must produce an explicit staged deletion path'
        Assert-McTrue -Condition (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'project-historical-sdk.json') -PathType Leaf)) -Message 'demoted record must be removed from proposed staging'
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

    $cmdFixture = Join-Path $RepoRoot 'tests\fixtures\probe.cmd'
    $cmd = Invoke-McProbe -Executable $cmdFixture -Arguments @('--version') -Provider 'fixture' -ProbeName 'cmd-script' -TimeoutMs 5000 -ResolutionScope 'collector-process'
    Assert-McEqual -Actual $cmd.status -Expected 'success' -Message 'cmd script probe must support paths with spaces'
    Assert-McEqual -Actual $cmd.exit_code -Expected 0 -Message 'cmd script probe exit code'
    Assert-McEqual -Actual (Get-McProbeVersionText -Probe $cmd) -Expected 'machinecontext-probe 1.2.3' -Message 'cmd script probe version output'
    Assert-McTrue -Condition ($cmd.used_shell -and $cmd.launcher -eq 'cmd') -Message 'cmd script probe must record explicit cmd launcher'
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

    $failureEvents = @(Get-McProviderFailureEvents -Failures @(
            [pscustomobject][ordered]@{ provider = 'runtimes-package-managers-toolchain'; health = 'failed'; message = 'fixture' },
            [pscustomobject][ordered]@{ provider = 'nvidia-smi'; health = 'timed_out'; message = 'fixture' }
        ))
    Assert-McTrue -Condition (@($failureEvents | Where-Object { $_.id -eq 'node' -and $_.provider -eq 'runtimes-package-managers-toolchain' }).Count -ge 1) -Message 'mapped provider failures must mark their entities unverified'
    Assert-McTrue -Condition (@($failureEvents | Where-Object { $_.provider -eq 'nvidia-smi' }).Count -eq 0) -Message 'providers without an entity map must contribute no entity-level failure events'
}

Invoke-McTest -Name 'provider diagnostics and local state' -Body {
    $diagnostics = New-McDiagnosticsContext -Mode Quick
    [void](Add-McProviderDiagnostic -Diagnostics $diagnostics -Provider 'fixture-success' -Health success -DurationMs 4.2 -ResultCount 2 -CoverageComplete $true)
    [void](Add-McProviderDiagnostic -Diagnostics $diagnostics -Provider 'fixture-optional' -Health unavailable -Optional $true)
    [void](Add-McProviderDiagnostic -Diagnostics $diagnostics -Provider 'fixture-optional-timeout' -Health timed_out -Optional $true)
    Assert-McEqual -Actual (Get-McOverallProviderHealth -Providers $diagnostics.providers) -Expected 'success' -Message 'optional unavailable provider should not make the whole scan partial'

    $partialAudit = ConvertTo-McAuditClosureProjection -InputObject ([pscustomobject][ordered]@{
            generated_at = '2026-08-26T00:00:00Z'
            summary = [pscustomobject][ordered]@{
                state = 'partial'
                conflicts = @()
                canonical_unknowns = @('fixture accepted unknown', 'fixture open unknown')
                accepted_unknowns = @('fixture accepted unknown')
                open_unknowns = @('fixture open unknown')
                local_candidate_unknowns = @('fixture candidate')
            }
            entries = @([pscustomobject][ordered]@{ status = 'unresolved' })
        }) -Source '.local/audit-closure.json'
    Assert-McEqual -Actual $partialAudit.state -Expected 'partial' -Message 'audit closure with canonical unknowns must remain partial'
    Assert-McEqual -Actual $partialAudit.blocking.canonical_unknown_count -Expected 2 -Message 'audit closure canonical unknown count'
    Assert-McEqual -Actual $partialAudit.blocking.accepted_unknown_count -Expected 1 -Message 'audit closure accepted unknown count'
    Assert-McEqual -Actual $partialAudit.blocking.open_unknown_count -Expected 1 -Message 'audit closure open unknown count'
    Assert-McEqual -Actual $partialAudit.blocking.unresolved_entry_count -Expected 1 -Message 'audit closure unresolved entry count'
    Assert-McEqual -Actual $partialAudit.blocking.local_candidate_unknown_count -Expected 1 -Message 'audit closure candidate unknown count'

    $verifiedAudit = ConvertTo-McAuditClosureProjection -InputObject ([pscustomobject][ordered]@{
            generated_at = '2026-08-26T00:00:00Z'
            summary = [pscustomobject][ordered]@{
                state = 'verified'
                conflicts = @()
                canonical_unknowns = @('fixture accepted unknown')
                accepted_unknowns = @('fixture accepted unknown')
                open_unknowns = @()
                local_candidate_unknowns = @('candidate evidence is allowed')
            }
            entries = @()
        }) -Source '.local/audit-closure.json'
    Assert-McEqual -Actual $verifiedAudit.state -Expected 'verified' -Message 'closed audit with no blockers must be verified'

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
    $status = Update-McPublishedStatus -Status $status -Diagnostics $diagnostics -Mode 'Quick' -AuditClosure $partialAudit
    Assert-McEqual -Actual $status.provider_state -Expected 'verified' -Message 'provider state must reflect provider aggregate health'
    Assert-McEqual -Actual $status.state -Expected 'partial' -Message 'published state must remain partial until audit closure is verified'
    Assert-McEqual -Actual $status.audit_closure.state -Expected 'partial' -Message 'published status must expose audit closure state'
    $preservedVerifiedAt = [datetime]::Parse([string]$status.published_verification.verified_at).ToUniversalTime()
    $status = Update-McPublishedStatus -Status $status -Diagnostics $diagnostics -Mode 'Quick' -AuditClosure $verifiedAudit
    Assert-McEqual -Actual $status.state -Expected 'verified' -Message 'published state may be verified after both gates pass'
    Assert-McTrue -Condition ([string]$status.published_verification.verified_at -match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$') -Message 'published verification timestamps must remain invariant ISO'
    Assert-McEqual -Actual ([datetime]::Parse([string]$status.published_verification.verified_at).ToUniversalTime()) -Expected $preservedVerifiedAt -Message 'no-publish reconciliation must preserve the existing heartbeat timestamp'
    $status = Update-McPublishedStatus -Status $status -Diagnostics $diagnostics -Mode 'Quick' -AuditClosure $verifiedAudit -PublishHeartbeat
    Assert-McTrue -Condition ([datetime]::Parse([string]$status.published_verification.verified_at).ToUniversalTime() -gt $preservedVerifiedAt) -Message 'published verification heartbeat must refresh on explicit publish'

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

Invoke-McTest -Name 'verification entrypoint accepts omitted provider filter' -Body {
    $verifyScript = Join-Path $RepoRoot 'scripts\verify.ps1'
    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    $output = & $pwsh -NoLogo -NoProfile -File $verifyScript -Mode Quick 2>&1
    Assert-McEqual -Actual $LASTEXITCODE -Expected 0 -Message 'verify.ps1 without -Provider must complete successfully'
    $json = ($output -join [Environment]::NewLine) | ConvertFrom-Json -Depth 50
    Assert-McTrue -Condition (-not [string]::IsNullOrWhiteSpace([string]$json.run_id)) -Message 'verify.ps1 must return a run id'
    Assert-McTrue -Condition ($null -ne $json.providers) -Message 'verify.ps1 must return provider diagnostics'
    Assert-McEqual -Actual $json.note -Expected 'Verification is read-only; canonical context was not modified.' -Message 'verify.ps1 read-only note'
}

Invoke-McTest -Name 'audit closure review contract' -Body {
    $valid = [pscustomobject][ordered]@{
        schema_version = 1
        kind = 'initial-audit-closure'
        generated_at = '2026-08-26T00:00:00Z'
        source = 'fixture'
        run_ids = [pscustomobject][ordered]@{ fixture = 'run-1' }
        summary = [pscustomobject][ordered]@{
            state = 'verified'
            conflicts = @()
            canonical_unknowns = @('fixture accepted unknown')
            accepted_unknowns = @('fixture accepted unknown')
            open_unknowns = @()
            verified_negative_facts = @('fixture negative fact')
            local_candidate_unknowns = @('fixture candidate')
            idempotency = [pscustomobject][ordered]@{ fixture_repeat = $true }
        }
        entries = @([pscustomobject][ordered]@{
                id = 'fixture'
                status = 'verified'
                evidence = @('context/status.json')
                facts = @('fixture fact')
            })
    }
    $review = Test-McAuditClosureDocument -InputObject $valid -Source '.local/audit-closure.json'
    Assert-McTrue -Condition $review.ok -Message 'valid audit closure must pass the structural review'
    Assert-McTrue -Condition $review.read_only -Message 'audit closure review must be explicitly read-only'
    Assert-McEqual -Actual $review.entry_count -Expected 1 -Message 'audit closure review entry count'
    Assert-McEqual -Actual $review.run_id_count -Expected 1 -Message 'audit closure review run id count'
    Assert-McEqual -Actual $review.closure.state -Expected 'verified' -Message 'verified fixture projection'
    Assert-McEqual -Actual $review.closure.blocking.accepted_unknown_count -Expected 1 -Message 'accepted unknowns remain visible in review'

    $invalid = [pscustomobject][ordered]@{
        schema_version = 1
        kind = 'wrong-kind'
        generated_at = '2026-08-26T00:00:00Z'
        summary = $valid.summary
        entries = @(
            [pscustomobject][ordered]@{ id = 'duplicate'; status = 'verified' }
            [pscustomobject][ordered]@{ id = 'duplicate'; status = 'unknown' }
        )
    }
    $invalidReview = Test-McAuditClosureDocument -InputObject $invalid -Source '.local/audit-closure.json'
    Assert-McTrue -Condition (-not $invalidReview.ok) -Message 'invalid audit closure must fail the structural review'
    Assert-McTrue -Condition (@($invalidReview.errors | Where-Object { $_.code -eq 'audit_closure_kind' }).Count -eq 1) -Message 'invalid audit kind must be reported'
    Assert-McTrue -Condition (@($invalidReview.errors | Where-Object { $_.code -eq 'audit_closure_duplicate_entry_id' }).Count -eq 1) -Message 'duplicate audit entry ids must be reported'
}

Invoke-McTest -Name 'semantic review contract' -Body {
    $valid = [pscustomobject][ordered]@{
        schema_version = 1
        kind = 'g2-semantic-review-draft'
        generated_at = '2026-08-26T00:00:00Z'
        source = 'fixture evidence'
        canonical_write = $false
        project_suggestions = @([pscustomobject][ordered]@{
                id = 'fixture-project'
                current_status = 'unknown'
                review_bucket = 'likely-active'
                confidence = 'medium'
                evidence = [pscustomobject][ordered]@{ path = 'E:\Projects\Fixture'; tracked_dirty = $false }
                requires_confirmation = $true
            })
        semantic_suggestions = @([pscustomobject][ordered]@{
                topic = 'installation-conventions'
                suggestion = 'Fixture suggestion requires confirmation.'
                evidence = @('context/conventions.json')
                requires_confirmation = $true
            })
        unresolved_checks = @([pscustomobject][ordered]@{
                id = 'fixture-check'
                state = 'unverified'
                evidence = @('local evidence')
                absence_claim = $false
            })
    }
    $review = Test-McG2SemanticReviewDocument -InputObject $valid -Source '.local/g2-semantic-review.json'
    Assert-McTrue -Condition $review.ok -Message 'valid semantic review must pass the structural review'
    Assert-McTrue -Condition $review.read_only -Message 'semantic review must be explicitly read-only'
    Assert-McEqual -Actual $review.canonical_write -Expected $false -Message 'semantic review must prohibit canonical writes'
    Assert-McEqual -Actual $review.project_suggestion_count -Expected 1 -Message 'semantic review project suggestion count'
    Assert-McEqual -Actual $review.semantic_suggestion_count -Expected 1 -Message 'semantic review suggestion count'
    Assert-McEqual -Actual $review.unresolved_check_count -Expected 1 -Message 'semantic review unresolved check count'
    Assert-McTrue -Condition $review.requires_confirmation -Message 'semantic review must expose confirmation gate'

    $invalid = [pscustomobject][ordered]@{
        schema_version = 1
        kind = 'g2-semantic-review-draft'
        generated_at = '2026-08-26T00:00:00Z'
        source = 'fixture evidence'
        canonical_write = $true
        project_suggestions = $valid.project_suggestions
        semantic_suggestions = $valid.semantic_suggestions
        unresolved_checks = @([pscustomobject][ordered]@{
                id = 'unsafe-check'
                state = 'unresolved'
                evidence = @('local evidence')
                absence_claim = $true
            })
    }
    $invalidReview = Test-McG2SemanticReviewDocument -InputObject $invalid -Source '.local/g2-semantic-review.json'
    Assert-McTrue -Condition (-not $invalidReview.ok) -Message 'unsafe semantic review must fail the structural review'
    Assert-McTrue -Condition (@($invalidReview.errors | Where-Object { $_.code -eq 'semantic_review_canonical_write' }).Count -eq 1) -Message 'canonical write authorization must be rejected'
    Assert-McTrue -Condition (@($invalidReview.errors | Where-Object { $_.code -eq 'semantic_review_unsafe_absence_claim' }).Count -eq 1) -Message 'unsafe absence claims must be rejected'
}

Invoke-McTest -Name 'curation confirmation stays explicit and curated-only' -Body {
    $fixtureRoot = Join-Path $RepoRoot '.local\test-curation-confirmation'
    $confirmationPath = Join-Path $fixtureRoot 'valid.json'
    $softwareOnlyPath = Join-Path $fixtureRoot 'software-only.json'
    $unsafePath = Join-Path $fixtureRoot 'unsafe.json'
    $unknownPath = Join-Path $fixtureRoot 'unknown.json'
    $invalidEvidencePath = Join-Path $fixtureRoot 'invalid-evidence.json'
    $invalidTimestampPath = Join-Path $fixtureRoot 'invalid-timestamp.json'
    $offsetTimestampPath = Join-Path $fixtureRoot 'offset-timestamp.json'
    $projectLifecyclePath = Join-Path $fixtureRoot 'project-lifecycle.json'
    $softwareProjectStatusPath = Join-Path $fixtureRoot 'software-project-status.json'
    $projectPath = Join-Path $RepoRoot 'context\projects\project-github.com-whatnamed-morpho.json'
    $softwarePath = Join-Path $RepoRoot 'context\software\ai.json'
    $conventionsPath = Join-Path $RepoRoot 'context\conventions.json'
    try {
        [void](New-Item -ItemType Directory -Path $fixtureRoot -Force)
        $valid = [ordered]@{
            schema_version = 1
            kind = 'g2-curation-confirmation'
            confirmed = $true
            confirmed_at = '2026-08-26T00:00:00Z'
            source_review = '.local/g2-semantic-review.json'
            project_updates = @([ordered]@{
                    id = 'project-github.com-whatnamed-morpho'
                    curated = [ordered]@{
                        status = 'active'
                        purpose = 'fixture confirmation only'
                        constraints = @()
                    }
                    evidence_refs = @('.local/g2-semantic-review.json')
                })
            software_updates = @([ordered]@{
                    id = 'codex-cli'
                    curated = [ordered]@{ role = 'primary' }
                    evidence_refs = @('.local/g2-semantic-review.json')
                })
            conventions_update = [ordered]@{
                evidence_refs = @('.local/g2-semantic-review.json')
                meta = [ordered]@{ state = 'confirmed' }
                directories = [ordered]@{
                    known_roots = @([ordered]@{ path = 'E:\Projects'; kind = 'project-root' })
                }
            }
        }
        Write-McJson -Path $confirmationPath -InputObject $valid
        $beforeProject = (Get-FileHash -LiteralPath $projectPath -Algorithm SHA256).Hash
        $beforeSoftware = (Get-FileHash -LiteralPath $softwarePath -Algorithm SHA256).Hash
        $beforeConventions = (Get-FileHash -LiteralPath $conventionsPath -Algorithm SHA256).Hash
        $plan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $confirmationPath
    Assert-McTrue -Condition $plan.ok -Message 'valid confirmation should produce an applicable plan'
        Assert-McEqual -Actual @($plan.changes).Count -Expected 3 -Message 'project, software, and conventions updates should produce three proposed files'
        $proposedProject = $plan.proposed_documents[$projectPath]
        Assert-McEqual -Actual $proposedProject.curated.status -Expected 'active' -Message 'curation plan should update project curated status only in the proposal'
        Assert-McEqual -Actual $proposedProject.observed.local_path -Expected 'D:\Morpho' -Message 'curation plan must preserve project observed facts'
        Assert-McEqual -Actual (Get-FileHash -LiteralPath $projectPath -Algorithm SHA256).Hash -Expected $beforeProject -Message 'dry-run must not write project canonical data'
        Assert-McEqual -Actual (Get-FileHash -LiteralPath $softwarePath -Algorithm SHA256).Hash -Expected $beforeSoftware -Message 'dry-run must not write software canonical data'
    Assert-McEqual -Actual (Get-FileHash -LiteralPath $conventionsPath -Algorithm SHA256).Hash -Expected $beforeConventions -Message 'dry-run must not write conventions canonical data'

    $offsetTimestamp = Copy-McJsonObject -InputObject $valid
    $offsetTimestamp.confirmed_at = '2026-08-26T00:00:00+08:00'
    Write-McJson -Path $offsetTimestampPath -InputObject $offsetTimestamp
        $offsetTimestampPlan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $offsetTimestampPath
        Assert-McTrue -Condition $offsetTimestampPlan.ok -Message 'explicit non-UTC confirmation offsets must remain valid'

        $projectLifecycle = Copy-McJsonObject -InputObject $valid
        $projectLifecycle.project_updates[0].curated.status = 'paused'
        Write-McJson -Path $projectLifecyclePath -InputObject $projectLifecycle
        $projectLifecyclePlan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $projectLifecyclePath
        Assert-McTrue -Condition $projectLifecyclePlan.ok -Message 'project policy lifecycle status paused must be accepted'
        Assert-McEqual -Actual $projectLifecyclePlan.proposed_documents[$projectPath].curated.status -Expected 'paused' -Message 'project lifecycle status must remain curated-only in the proposal'

        $softwareProjectStatus = Copy-McJsonObject -InputObject $valid
        $softwareProjectStatus.software_updates[0].curated.status = 'paused'
        Write-McJson -Path $softwareProjectStatusPath -InputObject $softwareProjectStatus
        $softwareProjectStatusPlan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $softwareProjectStatusPath
        Assert-McTrue -Condition (-not $softwareProjectStatusPlan.ok) -Message 'project-only lifecycle status must not be accepted for software curation'
        Assert-McTrue -Condition (@($softwareProjectStatusPlan.errors | Where-Object code -eq 'curation_status_value').Count -gt 0) -Message 'software project-only status must report a status contract error'

        $softwareOnly = Copy-McJsonObject -InputObject $valid
        Remove-McObjectProperty -InputObject $softwareOnly -Name 'project_updates'
        Write-McJson -Path $softwareOnlyPath -InputObject $softwareOnly
        $softwareOnlyPlan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $softwareOnlyPath
        Assert-McTrue -Condition $softwareOnlyPlan.ok -Message 'a confirmation may omit project_updates when only software is confirmed'
        Assert-McEqual -Actual $softwareOnlyPlan.project_update_count -Expected 0 -Message 'omitted project updates must normalize to an empty set'
        Assert-McEqual -Actual $softwareOnlyPlan.software_update_count -Expected 1 -Message 'software-only confirmation count must remain accurate'

        $unsafe = [ordered]@{
            schema_version = 1
            kind = 'g2-curation-confirmation'
            confirmed = $true
            confirmed_at = '2026-08-26T00:00:00Z'
            source_review = '.local/g2-semantic-review.json'
            project_updates = @([ordered]@{
                    id = 'project-github.com-whatnamed-morpho'
                    curated = [ordered]@{ observed = [ordered]@{ present = $false } }
                    evidence_refs = @('.local/g2-semantic-review.json')
                })
            software_updates = @()
        }
        Write-McJson -Path $unsafePath -InputObject $unsafe
        $unsafePlan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $unsafePath
        Assert-McTrue -Condition (-not $unsafePlan.ok) -Message 'observed writes must be rejected by curation contract'
        Assert-McTrue -Condition (@($unsafePlan.errors | Where-Object code -eq 'curation_observed_write').Count -gt 0) -Message 'unsafe curation must report observed-write error'

    $unknown = Copy-McJsonObject -InputObject $valid
    $unknown.project_updates[0].id = 'project-does-not-exist'
    Write-McJson -Path $unknownPath -InputObject $unknown
    $unknownPlan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $unknownPath
    Assert-McTrue -Condition (-not $unknownPlan.ok) -Message 'unknown stable IDs must be rejected by curation planning'
    Assert-McTrue -Condition (@($unknownPlan.errors | Where-Object code -eq 'curation_unknown_id').Count -gt 0) -Message 'unknown curation IDs must be reported'

    $invalidEvidence = Copy-McJsonObject -InputObject $valid
    $invalidEvidence.project_updates[0].evidence_refs = @('invented evidence')
    Write-McJson -Path $invalidEvidencePath -InputObject $invalidEvidence
    $invalidEvidencePlan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $invalidEvidencePath
    Assert-McTrue -Condition (-not $invalidEvidencePlan.ok) -Message 'evidence outside the declared review must be rejected'
    Assert-McTrue -Condition (@($invalidEvidencePlan.errors | Where-Object code -eq 'curation_evidence_reference').Count -gt 0) -Message 'unproven evidence references must be reported'

    $invalidTimestamp = Copy-McJsonObject -InputObject $valid
    $invalidTimestamp.confirmed_at = 'not-a-timestamp'
    Write-McJson -Path $invalidTimestampPath -InputObject $invalidTimestamp
    $invalidTimestampPlan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $invalidTimestampPath
    Assert-McTrue -Condition (-not $invalidTimestampPlan.ok) -Message 'invalid confirmation timestamps must be rejected'
    Assert-McTrue -Condition (@($invalidTimestampPlan.errors | Where-Object code -eq 'curation_timestamp').Count -gt 0) -Message 'invalid confirmation timestamps must be reported'

    $empty = [ordered]@{
        schema_version = 1
        kind = 'g2-curation-confirmation'
        confirmed = $true
        confirmed_at = '2026-08-26T00:00:00Z'
        source_review = '.local/g2-semantic-review.json'
    }
    $emptyPath = Join-Path $fixtureRoot 'empty.json'
    Write-McJson -Path $emptyPath -InputObject $empty
    $emptyPlan = New-McCurationPlan -RepoRoot $RepoRoot -ConfirmationPath $emptyPath
    Assert-McTrue -Condition (-not $emptyPlan.ok) -Message 'an empty confirmation must be rejected'
    Assert-McTrue -Condition (@($emptyPlan.errors | Where-Object code -eq 'curation_empty').Count -gt 0) -Message 'empty confirmation must report curation_empty'
}
    finally {
        if (Test-Path -LiteralPath $fixtureRoot -PathType Container) {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
        }
    }
}

Invoke-McTest -Name 'network listener ownership stays local-only' -Body {
    Assert-McEqual -Actual (Get-McServiceExecutableName -PathName '"C:\Program Files\FlClash\FlClashHelperService.exe" --service') -Expected 'FlClashHelperService.exe' -Message 'service ownership parser must retain basename only'
    $currentProcessName = (Get-Process -Id $PID -ErrorAction Stop | Select-Object -First 1).ProcessName
    $listeners = @(Get-McNetworkListenerDiagnostics -Connections @(
            [pscustomobject][ordered]@{ LocalAddress = '127.0.0.1'; LocalPort = 7988; OwningProcess = $PID },
            [pscustomobject][ordered]@{ LocalAddress = '::1'; LocalPort = 10808; OwningProcess = 2147483647 }
        ))

    Assert-McEqual -Actual $listeners.Count -Expected 2 -Message 'allowlisted listeners must retain one local diagnostic per connection'
    $known = $listeners | Where-Object { $_.port -eq 7988 }
    Assert-McEqual -Actual $known.address_scope -Expected 'loopback' -Message 'loopback listener scope must be normalized'
    Assert-McEqual -Actual $known.process_name -Expected $currentProcessName -Message 'accessible owning process name must be recorded locally'
    Assert-McTrue -Condition ($null -ne $known.PSObject.Properties['parent_process_name']) -Message 'parent process ownership must remain a local diagnostic field'
    Assert-McTrue -Condition ($null -ne $known.PSObject.Properties['service_name']) -Message 'service ownership must remain a local diagnostic field'
    $unknown = $listeners | Where-Object { $_.port -eq 10808 }
    Assert-McEqual -Actual $unknown.process_name -Expected $null -Message 'inaccessible owning process must remain unknown'
    Assert-McEqual -Actual $unknown.parent_process_name -Expected $null -Message 'inaccessible parent ownership must remain unknown'
    Assert-McEqual -Actual $unknown.local_address -Expected '::1' -Message 'local address evidence must remain local-only and deterministic'
}

Invoke-McTest -Name 'project activity remains local-only' -Body {
    $activity = Get-McProjectActivityObservation -Candidates @([pscustomobject][ordered]@{
            id = 'machinecontext-fixture'
            path = $RepoRoot
            verified = $true
            promotion_eligible = $true
        })
    Assert-McEqual -Actual @($activity.value).Count -Expected 0 -Message 'project activity must not create canonical observations'
    Assert-McEqual -Actual $activity.health -Expected 'success' -Message 'current repository activity probe health'
    Assert-McEqual -Actual @($activity.local.project_activity).Count -Expected 1 -Message 'eligible project must produce one local activity record'
    Assert-McEqual -Actual $activity.local.project_activity[0].verification -Expected 'verified' -Message 'project activity probes must verify the fixture repository'
    Assert-McEqual -Actual $activity.local.project_activity[0].probe_status.tracked_status -Expected 'success' -Message 'tracked-only status probe must complete successfully'
    Assert-McTrue -Condition ($activity.local.project_activity[0].tracked_dirty -is [bool]) -Message 'tracked-only status must produce an explicit Boolean'
    Assert-McTrue -Condition (-not [string]::IsNullOrWhiteSpace([string]$activity.local.project_activity[0].last_commit_at)) -Message 'last commit timestamp must be normalized locally'

    $missing = Get-McProjectActivityObservation -Candidates @([pscustomobject][ordered]@{
            id = 'missing-project-fixture'
            path = (Join-Path $RepoRoot 'tests\fixtures\__missing_project_activity__')
            verified = $true
            promotion_eligible = $true
        })
    Assert-McEqual -Actual $missing.health -Expected 'partial' -Message 'missing project activity must degrade optional provider health'
    Assert-McEqual -Actual $missing.local.project_activity[0].verification -Expected 'unverified' -Message 'missing project activity must remain unverified'
    Assert-McEqual -Actual $missing.local.project_activity[0].tracked_dirty -Expected $null -Message 'failed tracked status must remain unknown'
}

# ── Configuration projection (AI config profiles + MCP inventory) ──
. (Join-Path $RepoRoot 'scripts\collectors\config-profiles.ps1')
$configFixtureRoot = Join-Path $RepoRoot 'tests\fixtures\config-profiles'

Invoke-McTest -Name 'YAML subset parser handles mappings, sequences, scalars, and Unicode' -Body {
    $yaml = @'
shellPath: D:\Git\Git\bin\bash.exe
count: 42
enabled: true
disabled: false
nothing: null
quoted: "a: b # c"
chinese: 测试模型
list:
  - first
  - second
providers:
  demo:
    modelOverrides:
      model-a:
        contextWindow: 372000
    models:
      - id: model-a
        name: 模型 A
        input:
          - text
        thinking:
          efforts:
            - low
            - max
'@
    $parsed = Read-McConfigYamlText -Text $yaml
    Assert-McEqual -Actual $parsed.shellPath -Expected 'D:\Git\Git\bin\bash.exe' -Message 'YAML scalar string'
    Assert-McEqual -Actual $parsed.count -Expected 42 -Message 'YAML integer scalar'
    Assert-McEqual -Actual $parsed.enabled -Expected $true -Message 'YAML boolean true'
    Assert-McEqual -Actual $parsed.disabled -Expected $false -Message 'YAML boolean false'
    Assert-McEqual -Actual $parsed.nothing -Expected $null -Message 'YAML null scalar'
    Assert-McEqual -Actual $parsed.quoted -Expected 'a: b # c' -Message 'YAML quoted scalar keeps colon and hash'
    Assert-McEqual -Actual $parsed.chinese -Expected '测试模型' -Message 'YAML Unicode scalar'
    Assert-McEqual -Actual (@($parsed.list).Count) -Expected 2 -Message 'YAML scalar sequence'
    Assert-McEqual -Actual $parsed.providers.demo.modelOverrides.'model-a'.contextWindow -Expected 372000 -Message 'YAML nested mapping'
    $modelArray = @($parsed.providers.demo.models)
    Assert-McEqual -Actual $modelArray.Count -Expected 1 -Message 'single-item YAML sequence must stay an array'
    Assert-McEqual -Actual $modelArray[0].id -Expected 'model-a' -Message 'YAML sequence-of-mapping item'
    Assert-McEqual -Actual (@($modelArray[0].thinking.efforts).Count) -Expected 2 -Message 'YAML nested sequence inside sequence item'
}

Invoke-McTest -Name 'credential key denylist and env-name shapes' -Body {
    Assert-McTrue -Condition (Test-McSensitiveConfigKeyName -Name 'apiKey') -Message 'apiKey must be denied'
    Assert-McTrue -Condition (Test-McSensitiveConfigKeyName -Name 'api_key') -Message 'api_key must be denied'
    Assert-McTrue -Condition (Test-McSensitiveConfigKeyName -Name 'apiKeyPool') -Message 'apiKeyPool must be denied'
    Assert-McTrue -Condition (Test-McSensitiveConfigKeyName -Name 'refreshToken') -Message 'refreshToken must be denied'
    Assert-McTrue -Condition (Test-McSensitiveConfigKeyName -Name 'credentials') -Message 'credentials must be denied'
    Assert-McTrue -Condition (-not (Test-McSensitiveConfigKeyName -Name 'authHeader')) -Message 'authHeader must stay allowed'
    Assert-McTrue -Condition (-not (Test-McSensitiveConfigKeyName -Name 'authMode')) -Message 'authMode must stay allowed'
    Assert-McTrue -Condition (-not (Test-McSensitiveConfigKeyName -Name 'credentialEnvName')) -Message 'credentialEnvName projection key must stay allowed'
    Assert-McTrue -Condition (Test-McEnvVarNameShape -Value 'TOKENRHYTHM_API_KEY') -Message 'environment variable name shape accepted'
    Assert-McTrue -Condition (-not (Test-McEnvVarNameShape -Value 'sk-test-do-not-publish')) -Message 'secret-like value must not count as env name'
    Assert-McTrue -Condition (-not (Test-McEnvVarNameShape -Value 'lowercase_name')) -Message 'lowercase value must not count as env name'
}

Invoke-McTest -Name 'OMP fixture projection keeps source-native fields and env-name credentials only' -Body {
    $profile = Get-McOmpConfigProfile -AgentRoot (Join-Path $configFixtureRoot 'omp')
    Assert-McEqual -Actual $profile.id -Expected 'omp-config' -Message 'OMP profile id'
    Assert-McEqual -Actual ([string]$profile.observed.projection.config.shellPath) -Expected 'D:\Git\Git\bin\bash.exe' -Message 'OMP shellPath projected'
    Assert-McEqual -Actual ([string]$profile.observed.projection.config.modelRoles.default) -Expected 'tokenrhythm/test-model:max' -Message 'OMP model role projected'
    $providers = $profile.observed.projection.models.providers
    Assert-McEqual -Actual ([string]$providers.tokenrhythm.credentialEnvName) -Expected 'TESTFIXTURE_API_KEY' -Message 'tokenrhythm apiKey projected as env name'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $providers.tokenrhythm -Name 'apiKey')) -Message 'apiKey key must not survive projection'
    Assert-McTrue -Condition (@($profile.observed.credential_env_names) -contains 'TESTFIXTURE_API_KEY') -Message 'credential_env_names records the env name'
    $leakyText = ConvertTo-McJsonText -InputObject $profile
    Assert-McTrue -Condition ($leakyText -notmatch 'sk-test-do-not-publish') -Message 'OMP projection must not contain the fake key value'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $providers.'leaky-provider' -Name 'credentialEnvName')) -Message 'non-env-name apiKey must not become a credential reference'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $providers.'leaky-provider' -Name 'headers')) -Message 'unknown provider fields must be dropped by the per-field allowlist'
    Assert-McTrue -Condition (@($profile.observed.projection.unprojected_keys) -contains 'omp.models.providers.leaky-provider.headers') -Message 'dropped unknown provider fields must be recorded by path'
    Assert-McTrue -Condition (@($profile.observed.projection.unprojected_keys) -contains 'omp.models.providers.tokenrhythm.models[0].compat.futureFlag') -Message 'unknown compat fields must be dropped by the nested allowlist'
    $redactedKeys = @($profile.observed.redactions | Where-Object { $_.reason -eq 'credential-value' })
    Assert-McTrue -Condition ($redactedKeys.Count -ge 1) -Message 'OMP projection must record the redacted credential field'
    $tokenrhythmModels = @($providers.tokenrhythm.models)
    Assert-McEqual -Actual $tokenrhythmModels.Count -Expected 1 -Message 'single-model sequence must survive as array'
    Assert-McEqual -Actual ([string]$tokenrhythmModels[0].thinking.defaultLevel) -Expected 'max' -Message 'source-native thinking fields preserved'
    Assert-McEqual -Actual ([bool]$tokenrhythmModels[0].compat.supportsReasoningEffort) -Expected $true -Message 'allowlisted compat leaf preserved'
    $leakyModels = @($providers.'leaky-provider'.models)
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $leakyModels[0] -Name 'contextWindow')) -Message 'scalar-leaf fields must reject unexpected nested mappings'
    Assert-McEqual -Actual @($profile.observed.redactions | Where-Object { $_.path -eq 'omp.models.providers.leaky-provider.models[0].contextWindow' -and $_.reason -eq 'unsupported-value' }).Count -Expected 1 -Message 'rejected scalar-leaf mapping must be recorded as a redaction'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $leakyModels[0] -Name 'compat')) -Message 'nested-object schemas must reject scalar values'
    Assert-McEqual -Actual @($profile.observed.redactions | Where-Object { $_.path -eq 'omp.models.providers.leaky-provider.models[0].compat' -and $_.reason -eq 'unsupported-value' }).Count -Expected 1 -Message 'rejected scalar compat must be recorded as a redaction'
    Assert-McEqual -Actual $leakyModels.Count -Expected 1 -Message 'scalar items inside mapping sequences must be rejected'
    Assert-McEqual -Actual @($profile.observed.redactions | Where-Object { $_.path -eq 'omp.models.providers.leaky-provider.models[1]' -and $_.reason -eq 'unsupported-value' }).Count -Expected 1 -Message 'rejected scalar sequence item must be recorded as a redaction'
    $ompProfileText = ConvertTo-McJsonText -InputObject $profile
    Assert-McTrue -Condition ($ompProfileText -notmatch 'opaque-secret-value') -Message 'OMP projection must not contain scalar values rejected by nested-object schemas'
    Assert-McTrue -Condition ($ompProfileText -notmatch 'opaque-model-shape-value') -Message 'OMP projection must not contain scalar items rejected by mapping sequences'
    $first = ConvertTo-McJsonText -InputObject $profile
    $second = ConvertTo-McJsonText -InputObject $profile
    Assert-McEqual -Actual $first -Expected $second -Message 'OMP profile serialization must be deterministic'
}

Invoke-McTest -Name 'DSH fixture projection sanitizes URLs and credential env references' -Body {
    $profile = Get-McDshConfigProfile -ConfigRoot (Join-Path $configFixtureRoot 'dsh')
    Assert-McEqual -Actual $profile.id -Expected 'dsh-config' -Message 'DSH profile id'
    Assert-McEqual -Actual ([string]$profile.observed.projection.'agent-default-model'.provider) -Expected 'testrhythm' -Message 'DSH default model provider projected'
    $testrhythm = $profile.observed.projection.'llm-pi-ai'.providers.testrhythm
    Assert-McEqual -Actual ([string]$testrhythm.credentialEnvName) -Expected 'TESTFIXTURE_API_KEY' -Message 'DSH apiKeyEnv projected as env name'
    Assert-McEqual -Actual ([string]$testrhythm.baseURL) -Expected 'https://tokenrhythm.example.com/v1' -Message 'DSH baseURL kept when clean'
    Assert-McEqual -Actual (@($testrhythm.models).Count) -Expected 2 -Message 'DSH model sequence projected'
    $firstDshModel = @($testrhythm.models)[0]
    Assert-McEqual -Actual ([string]$firstDshModel.reasoningEfforts.max) -Expected 'max' -Message 'DSH reasoning effort mapping projected as strict scalars'
    Assert-McEqual -Actual ([string]$firstDshModel.input[0]) -Expected 'text' -Message 'DSH model input sequence projected'
    Assert-McEqual -Actual ([string](@($testrhythm.models)[1].input)) -Expected 'text' -Message 'DSH scalar model leaf projected'
    $badholder = $profile.observed.projection.'llm-pi-ai'.providers.badholder
    Assert-McEqual -Actual ([string]$badholder.baseURL) -Expected 'https://leaky.example.com/v1' -Message 'credential-bearing URL must be sanitized'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $badholder -Name 'credentialEnvName')) -Message 'raw credential value must not become env name'
    Assert-McEqual -Actual ([string]$profile.observed.projection.'llm-deepseek'.baseURL) -Expected 'https://deepseek-mirror.example.com/v1' -Message 'provider-shaped llm section projected'
    Assert-McTrue -Condition (@($profile.observed.credential_env_names) -contains 'TESTFIXTURE_API_KEY') -Message 'DSH credential env names collected'
    $profileText = ConvertTo-McJsonText -InputObject $profile
    Assert-McTrue -Condition ($profileText -notmatch 'fake-refresh-token') -Message 'DSH projection must not contain the fake credential value'
    Assert-McTrue -Condition ($profileText -notmatch 'user:pass') -Message 'DSH projection must not contain userinfo'
    Assert-McEqual -Actual ([string]$profile.observed.projection.'agent-presets'.default) -Expected 'pristine' -Message 'DSH agent preset default projected'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $testrhythm -Name 'headers')) -Message 'unknown DSH provider fields must be dropped by the per-field allowlist'
    Assert-McTrue -Condition (@($profile.observed.projection.unprojected_keys) -contains 'dsh.llm-pi-ai.providers.testrhythm.headers') -Message 'DSH dropped unknown provider fields must be recorded by path'
}

Invoke-McTest -Name 'ZCode fixture projection drops apiKey values and keeps model semantics' -Body {
    $profile = Get-McZcodeConfigProfile -AppDataRoot (Join-Path $configFixtureRoot 'zcode') -UserProfileRoot $null
    Assert-McEqual -Actual $profile.id -Expected 'zcode-config' -Message 'ZCode profile id'
    $providers = $profile.observed.projection.providers
    $bigmodel = $providers.'builtin:bigmodel'
    Assert-McEqual -Actual ([string]$bigmodel.baseURL) -Expected 'https://bigmodel.example.com/api/anthropic' -Message 'ZCode baseURL projected'
    Assert-McEqual -Actual ([bool]$bigmodel.'credential_configured') -Expected $true -Message 'ZCode credential presence recorded as boolean'
    $model = $bigmodel.models.'Test-GLM'
    Assert-McEqual -Actual ([string]$model.reasoning.defaultVariant) -Expected 'max' -Message 'ZCode reasoning variants projected'
    Assert-McEqual -Actual ([string]$model.modalities.input[1]) -Expected 'image' -Message 'ZCode modality list projected'
    $profileText = ConvertTo-McJsonText -InputObject $profile
    Assert-McTrue -Condition ($profileText -notmatch 'sk-test-do-not-publish') -Message 'ZCode projection must not contain the fake key value'
    Assert-McTrue -Condition ($profileText -notmatch 'fake-refresh-token') -Message 'ZCode projection must not contain the fake credential value'
    $credentialRedactions = @($profile.observed.redactions | Where-Object { $_.reason -eq 'credential-value' })
    Assert-McEqual -Actual $credentialRedactions.Count -Expected 2 -Message 'both fake keys must be recorded as redacted'
}

Invoke-McTest -Name 'ZCode profile never promotes the userprofile copy when the active config is missing' -Body {
    $profile = Get-McZcodeConfigProfile -AppDataRoot (Join-Path $configFixtureRoot 'missing-zcode') -UserProfileRoot (Join-Path $configFixtureRoot 'zcode')
    Assert-McTrue -Condition ($null -eq $profile) -Message 'missing active config must yield no profile instead of parsing the stale userprofile copy'
}

Invoke-McTest -Name 'OpenCodex fixture projection preserves routing semantics without credentials' -Body {
    $profile = Get-McOpencodexConfigProfile -ConfigRoot (Join-Path $configFixtureRoot 'opencodex')
    Assert-McEqual -Actual $profile.id -Expected 'opencodex-config' -Message 'OpenCodex profile id'
    $projection = $profile.observed.projection
    Assert-McEqual -Actual ([int]$projection.port) -Expected 10100 -Message 'OpenCodex listen port projected'
    Assert-McEqual -Actual ([string]$projection.defaultProvider) -Expected 'testai' -Message 'OpenCodex default provider projected'
    $testai = $projection.providers.testai
    Assert-McEqual -Actual (@($testai.models).Count) -Expected 3 -Message 'OpenCodex model list projected'
    Assert-McEqual -Actual ([int]$testai.modelContextWindows.'test-a') -Expected 272000 -Message 'OpenCodex per-model context window projected'
    Assert-McEqual -Actual ([bool]$testai.'credential_configured') -Expected $true -Message 'OpenCodex credential pool recorded as boolean'
    $mirror = $projection.providers.mirror
    Assert-McEqual -Actual ([string]$mirror.baseUrl) -Expected 'https://mirror.example.com/v1' -Message 'credential-bearing upstream URL sanitized'
    Assert-McEqual -Actual ([string]$projection.claudeCode.desktopProfile.defaults.sonnet) -Expected 'test-a' -Message 'claudeCode desktop defaults projected'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $testai -Name 'headers')) -Message 'unknown OpenCodex provider fields must be dropped by the per-field allowlist'
    Assert-McTrue -Condition (@($projection.unprojected_keys) -contains 'opencodex.providers.testai.headers') -Message 'OpenCodex dropped unknown provider fields must be recorded by path'
    Assert-McEqual -Actual ([string]$testai.modelReasoningEffortMap.'test-a'.low) -Expected 'medium' -Message 'OpenCodex effort map scalars projected'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $testai.modelReasoningEffortMap.'test-a' -Name 'sneaky')) -Message 'nested mappings under strict effort maps must be rejected'
    Assert-McEqual -Actual @($profile.observed.redactions | Where-Object { $_.path -eq 'opencodex.providers.testai.modelReasoningEffortMap.test-a.sneaky' -and $_.reason -eq 'unsupported-value' }).Count -Expected 1 -Message 'rejected nested effort-map mapping must be recorded as a redaction'
    Assert-McEqual -Actual @($projection.disabledModels).Count -Expected 1 -Message 'single-entry model lists must stay arrays'
    Assert-McEqual -Actual ([string]$projection.disabledModels[0]) -Expected 'testai/test-old' -Message 'disabledModels entry preserved'
    $profileText = ConvertTo-McJsonText -InputObject $profile
    Assert-McTrue -Condition ($profileText -notmatch 'sk-test-do-not-publish') -Message 'OpenCodex projection must not contain the fake key value'
    Assert-McTrue -Condition ($profileText -notmatch 'fake-refresh-token') -Message 'OpenCodex projection must not contain the fake credential value'
    Assert-McTrue -Condition ($profileText -notmatch 'pool-token-one') -Message 'OpenCodex projection must not contain pool tokens'
    Assert-McTrue -Condition ($profileText -notmatch 'opaque-mapping-value') -Message 'OpenCodex projection must not contain nested mapping values rejected by strict specs'
}

Invoke-McTest -Name 'TOML top-level scalar reader stays above table headers' -Body {
    $toml = @'
model = "gpt-5.6-terra"
model_context_window = 372000
auto_compact = true
quoted = 'single-quoted'

[mcp_servers.pencil]
command = "pencil-exe"
'@
    $parsed = Get-McTomlTopLevelScalars -Text $toml
    Assert-McEqual -Actual ([string]$parsed.model) -Expected 'gpt-5.6-terra' -Message 'TOML top-level double-quoted string'
    Assert-McEqual -Actual ([string]$parsed.quoted) -Expected 'single-quoted' -Message 'TOML top-level single-quoted string'
    Assert-McEqual -Actual ([long]$parsed.model_context_window) -Expected 372000 -Message 'TOML top-level integer'
    Assert-McEqual -Actual ([bool]$parsed.auto_compact) -Expected $true -Message 'TOML top-level boolean'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $parsed -Name 'command')) -Message 'table keys must not be parsed by the top-level reader'
}

Invoke-McTest -Name 'Codex CLI profile projects shared config context settings only' -Body {
    $profile = Get-McCodexConfigProfile -ConfigPath (Join-Path $configFixtureRoot 'codex-cli\config.toml')
    Assert-McEqual -Actual $profile.id -Expected 'codex-cli-config' -Message 'Codex profile id'
    $projection = $profile.observed.projection
    Assert-McEqual -Actual ([string]$projection.model) -Expected 'gpt-5.6-terra' -Message 'Codex model projected'
    Assert-McEqual -Actual ([long]$projection.model_context_window) -Expected 372000 -Message 'Codex context window projected'
    Assert-McEqual -Actual ([long]$projection.model_auto_compact_token_limit) -Expected 330000 -Message 'Codex auto compact limit projected'
    Assert-McEqual -Actual ([string]$projection.model_reasoning_effort) -Expected 'xhigh' -Message 'Codex reasoning effort projected'
    Assert-McTrue -Condition (@($projection.unprojected_keys) -contains 'codex-cli.personality') -Message 'unknown top-level keys must be recorded by name'
    Assert-McTrue -Condition (@($projection.unprojected_keys) -contains 'codex-cli.disable_response_storage') -Message 'non-allowlisted top-level keys must be recorded by name'
    $profileText = ConvertTo-McJsonText -InputObject $profile
    Assert-McTrue -Condition ($profileText -notmatch 'sk-test-do-not-publish') -Message 'Codex profile must not contain table credential material'
    Assert-McTrue -Condition ($profileText -notmatch 'pencil-exe') -Message 'Codex profile must not contain mcp table content'
    Assert-McTrue -Condition ($profileText -notmatch 'secret-exe') -Message 'Codex profile must not contain unknown table commands'
    $findings = [System.Collections.Generic.List[object]]::new()
    Validate-McConfigProfileRecord -Record $profile -Findings $findings -Path 'test'
    Assert-McEqual -Actual @($findings).Count -Expected 0 -Message 'good Codex profile must validate cleanly'
}

Invoke-McTest -Name 'Qoder fixture profile keeps plugins and defers MCP servers' -Body {
    $profile = Get-McQoderConfigProfile -SettingsPath (Join-Path $configFixtureRoot 'qoder\settings.json')
    Assert-McEqual -Actual $profile.id -Expected 'qoder-config' -Message 'Qoder profile id'
    $projection = $profile.observed.projection
    Assert-McEqual -Actual ([bool]$projection.enabledPlugins.'alpha-plugin@qoder-marketplace') -Expected $true -Message 'Qoder enabled plugin projected'
    Assert-McEqual -Actual ([bool]$projection.enabledPlugins.'beta-plugin@qoderapp-bundler') -Expected $false -Message 'Qoder disabled plugin projected'
    Assert-McTrue -Condition (@($projection.unprojected_keys) -contains 'qoder.mcpServers') -Message 'MCP declarations must be recorded by name and projected in the MCP inventory'
    Assert-McTrue -Condition (@($projection.unprojected_keys) -contains 'qoder.unknownTopLevel') -Message 'unknown top-level keys must be recorded by name'
    $routerFile = @($profile.source.files | Where-Object { $_.role -eq 'sensitive-config' })[0]
    Assert-McTrue -Condition ($null -ne $routerFile) -Message 'mcp-router.json must be recorded as a sensitive config file'
    $profileText = ConvertTo-McJsonText -InputObject $profile
    Assert-McTrue -Condition ($profileText -notmatch 'fixture-unknown-value') -Message 'unknown top-level values must not reach the projection'
    $findings = [System.Collections.Generic.List[object]]::new()
    Validate-McConfigProfileRecord -Record $profile -Findings $findings -Path 'test'
    Assert-McEqual -Actual @($findings).Count -Expected 0 -Message 'good Qoder profile must validate cleanly'
}

Invoke-McTest -Name 'MCP inventory keeps safe args and drops credential-bearing arguments' -Body {
    $mcp = Get-McMcpInventoryRecord `
        -ClaudeConfigPath (Join-Path $configFixtureRoot 'mcp\claude.json') `
        -GeminiSettingsPath (Join-Path $configFixtureRoot 'mcp\gemini-settings.json') `
        -CodexConfigPath (Join-Path $configFixtureRoot 'mcp\codex-config.toml') `
        -CursorMcpPath (Join-Path $configFixtureRoot 'mcp\cursor-mcp.json') `
        -QoderSettingsPath (Join-Path $configFixtureRoot 'qoder\settings.json')
    $servers = @($mcp.observed.servers)
    Assert-McEqual -Actual $servers.Count -Expected 6 -Message 'MCP servers collected from all five sources'
    $qoderServer = $servers | Where-Object { $_.tool -eq 'qoder' }
    Assert-McEqual -Actual ([string]$qoderServer.name) -Expected 'fixture-github' -Message 'Qoder MCP server collected'
    Assert-McEqual -Actual ([string]$qoderServer.url) -Expected 'https://mcp.fixture.example.com/mcp' -Message 'Qoder MCP url kept (sanitized)'
    Assert-McEqual -Actual ([string]$qoderServer.transport) -Expected 'http' -Message 'Qoder MCP transport projected'
    $qoderText = ConvertTo-McJsonText -InputObject $mcp
    Assert-McTrue -Condition ($qoderText -notmatch 'mcp-router.fixture.example.com') -Message 'Qoder router-only qoder_url must never reach the MCP inventory'
    $http = $servers | Where-Object name -eq 'fixture-http'
    Assert-McEqual -Actual ([string]$http.url) -Expected 'https://mcp.fixture.example.com/mcp' -Message 'safe MCP URL kept'
    $safe = $servers | Where-Object name -eq 'fixture-safe-stdio'
    Assert-McEqual -Actual (@($safe.args) -join ' ') -Expected '--app cursor --agent cli' -Message 'safe MCP args kept'
    $secret = $servers | Where-Object name -eq 'fixture-secret-stdio'
    Assert-McTrue -Condition (@($secret.args) -notcontains '--token=sk-test-do-not-publish') -Message 'credential-bearing MCP arg must be dropped'
    Assert-McEqual -Actual (@($secret.args) -join ' ') -Expected '/c npx -y server@latest' -Message 'remaining MCP args preserved'
    Assert-McTrue -Condition (@($secret.args) -notcontains '--token') -Message 'split-form credential flag must be dropped'
    Assert-McTrue -Condition (@($secret.args) -notcontains 'opaque-secret-value') -Message 'split-form credential value must be dropped with its flag'
    $geminiServer = $servers | Where-Object tool -eq 'gemini-cli'
    Assert-McEqual -Actual (@($geminiServer.args) -join ' ') -Expected '--app cursor --agent geminiCLI' -Message 'split --api-key pair must be dropped together'
    $codexServer = $servers | Where-Object tool -eq 'codex-cli'
    Assert-McEqual -Actual ([string]$codexServer.name) -Expected 'fixture-codex' -Message 'TOML MCP server parsed'
    Assert-McEqual -Actual (@($codexServer.args) -join ' ') -Expected '--app cursor --agent codexCLI' -Message 'split -H header pair must be dropped together'
    $mcpText = ConvertTo-McJsonText -InputObject $mcp
    Assert-McTrue -Condition ($mcpText -notmatch 'sk-test-do-not-publish') -Message 'MCP inventory must not contain the fake token value'
    Assert-McTrue -Condition ($mcpText -notmatch 'opaque-secret-value') -Message 'MCP inventory must not contain split-form credential values'
    Assert-McTrue -Condition ($mcpText -notmatch 'X-Api-Key') -Message 'MCP inventory must not contain header credential material'
    Assert-McTrue -Condition ($mcpText -notmatch 'fixture-user-id-must-not-leak') -Message 'MCP inventory must not leak unrelated config state'
    Assert-McTrue -Condition ($mcpText -notmatch 'fixture-uuid-must-not-leak') -Message 'MCP inventory must not leak account identifiers'
}

Invoke-McTest -Name 'config profile validation rejects sensitive keys and accepts good records' -Body {
    $findings = [System.Collections.Generic.List[object]]::new()
    $goodProfile = Get-McOmpConfigProfile -AgentRoot (Join-Path $configFixtureRoot 'omp')
    Validate-McConfigProfileRecord -Record $goodProfile -Findings $findings -Path 'test'
    Assert-McEqual -Actual @($findings).Count -Expected 0 -Message 'good OMP profile must validate cleanly'

    Set-McObjectProperty -InputObject $goodProfile.observed -Name 'source_state' -Value 'stale'
    Set-McObjectProperty -InputObject $goodProfile.observed -Name 'source_state_reason' -Value 'config source confirmed absent during scan'
    $staleFindings = [System.Collections.Generic.List[object]]::new()
    Validate-McConfigProfileRecord -Record $goodProfile -Findings $staleFindings -Path 'test'
    Assert-McEqual -Actual @($staleFindings).Count -Expected 0 -Message 'stale source_state with reason must validate cleanly'

    Set-McObjectProperty -InputObject $goodProfile.observed -Name 'source_state' -Value 'expired'
    $badStateFindings = [System.Collections.Generic.List[object]]::new()
    Validate-McConfigProfileRecord -Record $goodProfile -Findings $badStateFindings -Path 'test'
    Assert-McTrue -Condition (@($badStateFindings | Where-Object { $_.code -eq 'config_profile_source_state' }).Count -ge 1) -Message 'unknown source_state values must be rejected'

    $badProjection = [ordered]@{
        providers = [ordered]@{
            evil = [ordered]@{ apiKey = 'not-a-real-value' }
        }
    }
    $sensitive = Get-McSensitiveConfigKeyFindings -InputObject $badProjection
    Assert-McTrue -Condition (@($sensitive).Count -ge 1) -Message 'planted apiKey key must be detected in projections'
}

Invoke-McTest -Name 'config profile reconciliation writes index and preserves curated intent' -Body {
    $tempRoot = Join-Path $RepoRoot '.local\test-config-context'
    $aiRoot = Join-Path $tempRoot 'configs\ai'
    [void](New-Item -ItemType Directory -Path $aiRoot -Force)
    $existing = [pscustomobject][ordered]@{
        schema_version = 1
        id             = 'omp-config'
        kind           = 'ai-config-profile'
        tool           = 'omp'
        observed       = [pscustomobject][ordered]@{ projection = [pscustomobject][ordered]@{ stale = $true } }
        curated        = [pscustomobject][ordered]@{ notes = @('version pinned by user') }
    }
    Write-McJson -Path (Join-Path $aiRoot 'omp.json') -InputObject $existing

    $profile = Get-McOmpConfigProfile -AgentRoot (Join-Path $configFixtureRoot 'omp')
    $mcp = Get-McMcpInventoryRecord `
        -ClaudeConfigPath (Join-Path $configFixtureRoot 'mcp\claude.json') `
        -GeminiSettingsPath (Join-Path $configFixtureRoot 'mcp\gemini-settings.json') `
        -CodexConfigPath (Join-Path $configFixtureRoot 'mcp\codex-config.toml') `
        -CursorMcpPath (Join-Path $configFixtureRoot 'mcp\cursor-mcp.json')
    Merge-McConfigProfiles -ContextRoot $tempRoot -Profiles @($profile) -McpInventory $mcp

    $written = Read-McJson -Path (Join-Path $aiRoot 'omp.json')
    Assert-McEqual -Actual ([string]$written.curated.notes[0]) -Expected 'version pinned by user' -Message 'curated intent must survive config reconciliation'
    Assert-McTrue -Condition ($null -eq (Get-McObjectPropertyOrNull -InputObject $written.observed.projection -Name 'stale')) -Message 'stale projection must be replaced'
    Assert-McEqual -Actual ([string]$written.observed.projection.config.shellPath) -Expected 'D:\Git\Git\bin\bash.exe' -Message 'fresh projection written'

    $index = Read-McJson -Path (Join-Path $tempRoot 'configs\index.json')
    Assert-McTrue -Condition (@($index.modules | Where-Object { $_.path -eq 'ai/omp.json' }).Count -eq 1) -Message 'config index registers profile modules'
    Assert-McTrue -Condition (@($index.modules | Where-Object { $_.path -eq 'mcp.json' }).Count -eq 1) -Message 'config index registers MCP inventory'
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

Invoke-McTest -Name 'config reconciliation marks last-known profiles stale when sources are confirmed absent' -Body {
    $tempRoot = Join-Path $RepoRoot '.local\test-config-stale'
    $aiRoot = Join-Path $tempRoot 'configs\ai'
    [void](New-Item -ItemType Directory -Path $aiRoot -Force)
    $existing = [pscustomobject][ordered]@{
        schema_version = 1
        id             = 'omp-config'
        kind           = 'ai-config-profile'
        tool           = 'omp'
        observed       = [pscustomobject][ordered]@{ value_basis = 'configured-local'; source_state = 'current' }
        curated        = [pscustomobject][ordered]@{ notes = @('keep me') }
    }
    Write-McJson -Path (Join-Path $aiRoot 'omp.json') -InputObject $existing

    $missingState = [pscustomobject][ordered]@{ tool = 'omp'; state = 'source-missing' }
    Merge-McConfigProfiles -ContextRoot $tempRoot -Profiles @() -ProfileStates @($missingState) -McpInventory $null

    $written = Read-McJson -Path (Join-Path $aiRoot 'omp.json')
    Assert-McEqual -Actual ([string]$written.observed.source_state) -Expected 'stale' -Message 'confirmed source absence must mark the last-known profile stale'
    Assert-McEqual -Actual ([string]$written.observed.source_state_reason) -Expected 'config source confirmed absent during scan' -Message 'stale profiles must record the reason'
    Assert-McEqual -Actual ([string]$written.curated.notes[0]) -Expected 'keep me' -Message 'stale marking must preserve curated intent'

    $first = [System.IO.File]::ReadAllText((Join-Path $aiRoot 'omp.json'))
    Merge-McConfigProfiles -ContextRoot $tempRoot -Profiles @() -ProfileStates @($missingState) -McpInventory $null
    $second = [System.IO.File]::ReadAllText((Join-Path $aiRoot 'omp.json'))
    Assert-McEqual -Actual $second -Expected $first -Message 'stale marking must be byte-idempotent across runs'

    $index = Read-McJson -Path (Join-Path $tempRoot 'configs\index.json')
    $ompModule = @($index.modules | Where-Object { $_.path -eq 'ai/omp.json' })[0]
    Assert-McEqual -Actual ([string]$ompModule.source_state) -Expected 'stale' -Message 'config index must surface the stale state'
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
}

if ($failures.Count -gt 0) {
    Write-Host "FAILED $($failures.Count) assertion(s)"
    $failures | ForEach-Object { Write-Host " - $_" }
    exit 1
}

Write-Host 'All MachineContext tests passed.'
