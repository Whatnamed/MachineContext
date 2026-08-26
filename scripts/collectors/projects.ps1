Set-StrictMode -Version Latest

function ConvertTo-McActualPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    foreach ($pair in (Get-McEnvironmentPathMap)) {
        if ($expanded.StartsWith($pair.Token, [System.StringComparison]::OrdinalIgnoreCase)) {
            $environmentValue = [string]$pair.Value
            $expanded = $environmentValue + $expanded.Substring($pair.Token.Length)
            break
        }
    }
    return $expanded
}

function Get-McProjectSearchRoots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($root in @(Get-McCollectionRootsFromManifest -RepoRoot $RepoRoot)) {
        $actual = ConvertTo-McActualPath -Path $root
        if (Test-Path -LiteralPath $actual -PathType Container -ErrorAction SilentlyContinue) {
            [void]$roots.Add($actual)
        }
    }

    $defaults = @(
        'C:\Dev', 'D:\Dev', 'E:\Dev',
        'C:\Projects', 'D:\Projects', 'E:\Projects',
        'D:\Morpho', 'D:\联合设计工坊', 'E:\FlClash',
        (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) 'source'),
        (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) 'projects'),
        (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) 'Documents\GitHub')
    )
    foreach ($root in $defaults) {
        if ([string]::IsNullOrWhiteSpace([string]$root)) { continue }
        if (Test-Path -LiteralPath $root -PathType Container -ErrorAction SilentlyContinue) {
            [void]$roots.Add($root)
        }
    }

    $repoFull = (Resolve-Path -LiteralPath $RepoRoot).Path.TrimEnd('\')
    $result = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($root in $roots) {
        try {
            $full = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Path.TrimEnd('\')
            if ($full.Equals($repoFull, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($seen.Add($full)) { [void]$result.Add($full) }
        }
        catch {
        }
    }

    return @($result | Sort-Object)
}

function Get-McProjectPackageFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $manifests = [System.Collections.Generic.List[object]]::new()
    $runtimeRefs = [System.Collections.Generic.List[string]]::new()
    $packageRefs = [System.Collections.Generic.List[string]]::new()
    $commands = [ordered]@{}
    $packageManager = $null

    $packageJson = Join-Path $Path 'package.json'
    if (Test-Path -LiteralPath $packageJson -PathType Leaf -ErrorAction SilentlyContinue) {
        [void]$manifests.Add([pscustomobject][ordered]@{ path = ConvertTo-McNormalizedPath -Path $packageJson; kind = 'package-manifest' })
        try {
            $package = Read-McJson -Path $packageJson
            $declared = Get-McOptionalProperty -InputObject $package -Name 'packageManager'
            if (-not [string]::IsNullOrWhiteSpace([string]$declared) -and (Test-McPrivacySafeText -Text ([string]$declared))) {
                $packageManager = ([string]$declared).Trim()
                $packageName = ($packageManager -split '@')[0]
                if (-not [string]::IsNullOrWhiteSpace($packageName)) { [void]$packageRefs.Add($packageName) }
            }

            $scripts = Get-McOptionalProperty -InputObject $package -Name 'scripts'
            foreach ($scriptName in @('dev', 'start', 'build', 'test', 'lint', 'typecheck')) {
                $scriptValue = Get-McOptionalProperty -InputObject $scripts -Name $scriptName
                if ($scriptValue -is [string] -and $scriptValue.Length -le 240 -and (Test-McPrivacySafeText -Text $scriptValue)) {
                    $commands[$scriptName] = [string]$scriptValue
                }
            }
        }
        catch {
        }
    }

    $lockfiles = @(
        [pscustomobject]@{ name = 'pnpm-lock.yaml'; manager = 'pnpm' },
        [pscustomobject]@{ name = 'yarn.lock'; manager = 'yarn' },
        [pscustomobject]@{ name = 'package-lock.json'; manager = 'npm' },
        [pscustomobject]@{ name = 'bun.lockb'; manager = 'bun' },
        [pscustomobject]@{ name = 'bun.lock'; manager = 'bun' }
    )
    foreach ($lockfile in $lockfiles) {
        $lockPath = Join-Path $Path $lockfile.name
        if (Test-Path -LiteralPath $lockPath -PathType Leaf -ErrorAction SilentlyContinue) {
            [void]$manifests.Add([pscustomobject][ordered]@{ path = ConvertTo-McNormalizedPath -Path $lockPath; kind = 'lockfile' })
            if ([string]::IsNullOrWhiteSpace($packageManager)) { $packageManager = $lockfile.manager }
            if (-not $packageRefs.Contains($lockfile.manager)) { [void]$packageRefs.Add($lockfile.manager) }
        }
    }

    $otherManifests = @(
        [pscustomobject]@{ name = 'pyproject.toml'; kind = 'python-manifest'; runtime = 'python' },
        [pscustomobject]@{ name = 'requirements.txt'; kind = 'python-requirements'; runtime = 'python' },
        [pscustomobject]@{ name = 'Cargo.toml'; kind = 'rust-manifest'; runtime = 'rustc' },
        [pscustomobject]@{ name = 'go.mod'; kind = 'go-manifest'; runtime = 'go' },
        [pscustomobject]@{ name = 'pom.xml'; kind = 'java-manifest'; runtime = 'java' },
        [pscustomobject]@{ name = 'build.gradle'; kind = 'java-build'; runtime = 'java' },
        [pscustomobject]@{ name = 'build.gradle.kts'; kind = 'java-build'; runtime = 'java' },
        [pscustomobject]@{ name = 'pubspec.yaml'; kind = 'dart-manifest'; runtime = 'dart' },
        [pscustomobject]@{ name = 'CMakeLists.txt'; kind = 'cmake-manifest'; runtime = 'cmake' }
    )
    foreach ($manifest in $otherManifests) {
        $manifestPath = Join-Path $Path $manifest.name
        if (Test-Path -LiteralPath $manifestPath -PathType Leaf -ErrorAction SilentlyContinue) {
            [void]$manifests.Add([pscustomobject][ordered]@{ path = ConvertTo-McNormalizedPath -Path $manifestPath; kind = $manifest.kind })
            if (-not $runtimeRefs.Contains($manifest.runtime)) { [void]$runtimeRefs.Add($manifest.runtime) }
        }
    }

    return [pscustomobject][ordered]@{
        package_manager = $packageManager
        package_manager_refs = @($packageRefs | Sort-Object)
        runtime_refs = @($runtimeRefs | Sort-Object)
        manifests = @($manifests | Sort-Object path,kind)
        commands = [pscustomobject]$commands
    }
}

function Get-McProjectCandidateAtPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $gitPath = Join-Path $Path '.git'
    $gitExists = Test-Path -LiteralPath $gitPath -ErrorAction SilentlyContinue
    $package = Get-McProjectPackageFingerprint -Path $Path
    $hasManifest = @($package.manifests).Count -gt 0
    if (-not $gitExists -and -not $hasManifest) {
        return $null
    }

    $remote = $null
    $remoteProbe = $null
    if ($gitExists) {
        $remoteProbe = Invoke-McProbe -Executable 'git.exe' -Arguments @('-C', $Path, 'config', '--get', 'remote.origin.url') -Provider 'project-fingerprints' -ProbeName 'git-remote' -TimeoutMs 5000 -OutputCapBytes 4096
        if ($remoteProbe.status -eq 'success') {
            $remote = ConvertTo-McSafeRepositoryIdentity -Remote (Get-McProbeVersionText -Probe $remoteProbe)
        }
    }

    $normalizedPath = ConvertTo-McNormalizedPath -Path $Path -ResolveExisting
    $identity = if (-not [string]::IsNullOrWhiteSpace($remote)) { $remote } else { $normalizedPath }
    $projectId = New-McStableId -Kind 'project' -Identity $identity
    $evidence = [System.Collections.Generic.List[object]]::new()
    if ($gitExists) {
        [void]$evidence.Add([pscustomobject][ordered]@{ type = 'git_fingerprint'; path = ConvertTo-McNormalizedPath -Path $gitPath })
    }
    foreach ($manifest in @($package.manifests)) {
        [void]$evidence.Add([pscustomobject][ordered]@{ type = 'manifest_present'; path = [string]$manifest.path; kind = [string]$manifest.kind })
    }

    $observed = [ordered]@{
        local_path = $normalizedPath
        repository = $remote
        workspace_type = if ($gitExists -and $hasManifest) { 'git-project' } elseif ($gitExists) { 'git-repository' } else { 'manifest-project' }
        runtime_refs = @($package.runtime_refs)
        package_manager_refs = @($package.package_manager_refs)
        tool_refs = @()
        service_refs = @()
        manifests = @($package.manifests)
        commands = $package.commands
        local_endpoints = @()
        evidence = @($evidence)
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$package.package_manager)) {
        $observed.package_manager = [string]$package.package_manager
    }

    return [pscustomobject][ordered]@{
        candidate_id = $projectId
        id = $projectId
        kind_hint = 'project'
        name_hint = (Split-Path -Leaf $Path)
        path = $normalizedPath
        source = 'project-fingerprints'
        source_key = $normalizedPath
        confidence_hint = if ($gitExists) { 'high' } else { 'medium' }
        verified = $true
        promotion_eligible = [bool]$gitExists
        observed = [pscustomobject]$observed
        evidence = @($evidence)
    }
}

function Get-McProjectCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [ValidateRange(1, 6)]
        [int]$MaxDepth = 3,

        [ValidateRange(1, 1000)]
        [int]$MaxResults = 250
    )

    $candidates = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $skipNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('.git', 'node_modules', '.pnpm-store', '.yarn', 'dist', 'build', 'out', 'target', '.next', '.nuxt', '.venv', 'venv', '__pycache__', '.cache', 'coverage', 'vendor')) {
        [void]$skipNames.Add($name)
    }

    foreach ($root in (Get-McProjectSearchRoots -RepoRoot $RepoRoot)) {
        [void]$queue.Enqueue([pscustomobject]@{ path = $root; depth = 0 })
    }

    while ($queue.Count -gt 0 -and $candidates.Count -lt $MaxResults) {
        $item = $queue.Dequeue()
        $path = [string]$item.path
        try {
            $full = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path.TrimEnd('\')
            if (-not $visited.Add($full)) { continue }
            $attributes = (Get-Item -LiteralPath $full -ErrorAction Stop).Attributes
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }

            $candidate = Get-McProjectCandidateAtPath -Path $full
            if ($null -ne $candidate) {
                [void]$candidates.Add($candidate)
            }

            if ([int]$item.depth -ge $MaxDepth) { continue }
            foreach ($child in @(Get-ChildItem -LiteralPath $full -Force -Directory -ErrorAction Stop)) {
                if ($skipNames.Contains($child.Name)) { continue }
                if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                [void]$queue.Enqueue([pscustomobject]@{ path = $child.FullName; depth = ([int]$item.depth + 1) })
            }
        }
        catch {
            [void]$warnings.Add("project path unavailable: $path")
        }
    }

    $dedupe = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in $candidates) {
        if (-not $dedupe.ContainsKey([string]$candidate.id)) {
            $dedupe[[string]$candidate.id] = $candidate
        }
    }
    $items = @($dedupe.Values | Sort-Object id)
    $health = if ($warnings.Count -gt 0) { 'partial' } else { 'success' }
    return New-McProviderPayload -Value $items -Health $health -ResultCount $items.Count -Warnings @($warnings) -CoverageComplete $false
}
