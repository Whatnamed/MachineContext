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

function Test-McPathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Root
    )

    $pathValue = $Path.TrimEnd('\', '/')
    $rootValue = $Root.TrimEnd('\', '/')
    return $pathValue.Equals($rootValue, [System.StringComparison]::OrdinalIgnoreCase) -or $pathValue.StartsWith($rootValue + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-McCanonicalProjectPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $paths = [System.Collections.Generic.List[string]]::new()
    $indexPath = Join-Path $RepoRoot 'context\projects\index.json'
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf -ErrorAction SilentlyContinue)) {
        return @()
    }

    try {
        $index = Read-McJson -Path $indexPath
        foreach ($project in @($index.projects)) {
            $candidate = [string]$project.path
            if ([string]::IsNullOrWhiteSpace($candidate)) {
                continue
            }
            $actual = ConvertTo-McActualPath -Path $candidate
            if ([string]::IsNullOrWhiteSpace($actual)) {
                continue
            }
            try {
                $actual = (Resolve-Path -LiteralPath $actual -ErrorAction Stop).Path
            }
            catch {
            }
            $normalized = ConvertTo-McNormalizedPath -Path $actual -ResolveExisting
            if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $paths.Contains($normalized)) {
                [void]$paths.Add($normalized)
            }
        }
    }
    catch {
        return @()
    }

    return @($paths | Sort-Object)
}

function Get-McProjectRootPolicies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $policies = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $addPolicy = {
        param(
            [AllowNull()]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Kind,

            [Parameter(Mandatory)]
            [string]$Source,

            [Parameter(Mandatory)]
            [bool]$AutoPromote,

            [Parameter(Mandatory)]
            [int]$WalkDepth,

            [Parameter(Mandatory)]
            [int]$Priority
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return
        }
        $actual = ConvertTo-McActualPath -Path $Path
        if ([string]::IsNullOrWhiteSpace($actual)) {
            return
        }
        try {
            if (Test-Path -LiteralPath $actual -ErrorAction SilentlyContinue) {
                $actual = (Resolve-Path -LiteralPath $actual -ErrorAction Stop).Path
            }
        }
        catch {
        }
        $normalized = ConvertTo-McNormalizedPath -Path $actual -ResolveExisting
        if ([string]::IsNullOrWhiteSpace($normalized) -or -not $seen.Add($normalized + '|' + $Kind)) {
            return
        }
        [void]$policies.Add([pscustomobject][ordered]@{
                root         = $normalized
                kind         = $Kind
                source       = $Source
                auto_promote = $AutoPromote
                walk_depth   = $WalkDepth
                priority     = $Priority
            })
    }

    foreach ($root in @(Get-McCollectionRootsFromManifest -RepoRoot $RepoRoot)) {
        & $addPolicy -Path $root -Kind 'project-root' -Source 'conventions.known_roots' -AutoPromote $true -WalkDepth 5 -Priority 70
    }

    foreach ($root in @(
            'C:\Projects', 'D:\Projects', 'E:\Projects',
            (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) 'source'),
            (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) 'projects'),
            (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) 'Documents\GitHub')
        )) {
        & $addPolicy -Path $root -Kind 'project-root' -Source 'known-project-root' -AutoPromote $true -WalkDepth 5 -Priority 60
    }

    foreach ($root in @('C:\Dev', 'D:\Dev', 'E:\Dev')) {
        & $addPolicy -Path $root -Kind 'developer-root' -Source 'known-developer-root' -AutoPromote $false -WalkDepth 1 -Priority 20
    }
    foreach ($root in @('D:\联合设计工坊', 'E:\FlClash')) {
        & $addPolicy -Path $root -Kind 'workspace-root' -Source 'bootstrap/workspace-root' -AutoPromote $false -WalkDepth 1 -Priority 25
    }

    foreach ($root in @(
            'E:\Dev\flutter', 'E:\dev\flutter', 'D:\Git', 'D:\Node.js', 'D:\Go',
            'D:\Tools', 'D:\DSH', 'D:\VSCode', 'E:\VSCode', 'E:\Dev\uv',
            'E:\Dev\npm-global', 'E:\Codex'
        )) {
        & $addPolicy -Path $root -Kind 'tool-root' -Source 'bootstrap/tool-root' -AutoPromote $false -WalkDepth 0 -Priority 80
    }
    foreach ($root in @('E:\Dev\flutter')) {
        & $addPolicy -Path $root -Kind 'sdk-root' -Source 'bootstrap/sdk-root' -AutoPromote $false -WalkDepth 0 -Priority 90
    }
    foreach ($root in @(
            'E:\Dev\npm-cache',
            (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) '.cache'),
            (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) '.codex'),
            (Join-Path ([Environment]::GetEnvironmentVariable('USERPROFILE')) '.agent-reach-venv')
        )) {
        & $addPolicy -Path $root -Kind 'cache-root' -Source 'known-cache-root' -AutoPromote $false -WalkDepth 0 -Priority 100
    }

    # These locations were historical project hints, not a claim that the paths
    # still exist. Existing canonical projects outside the broad workspace roots
    # remain eligible, while more specific SDK/cache policies win on overlap.
    foreach ($root in @(
            'D:\Morpho',
            'D:\联合设计工坊\Morpho',
            'E:\FlClash\flclash-traffic-ledger',
            'E:\Codex\CodexBridge'
        )) {
        & $addPolicy -Path $root -Kind 'project-root' -Source 'bootstrap/project-root' -AutoPromote $true -WalkDepth 5 -Priority 75
    }

    foreach ($root in @(Get-McCanonicalProjectPaths -RepoRoot $RepoRoot)) {
        & $addPolicy -Path $root -Kind 'canonical-project' -Source 'canonical-project-index' -AutoPromote $true -WalkDepth 5 -Priority 65
    }

    return @($policies | Sort-Object @{ Expression = { ([string]$_.root).Length }; Descending = $true }, @{ Expression = { [int]$_.priority }; Descending = $true }, kind, root)
}

function Get-McProjectPathSegmentPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $segments = @($Path.Replace('/', '\') -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $skipSegments = @(
        '.git', '.open-next', '.vercel', '.turbo', '.dart_tool', '.gradle',
        '.idea', '.vs', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox',
        'node_modules', '.pnpm-store', '.yarn', '_npx', 'dist', 'build',
        'out', 'target', '.next', '.nuxt', '.venv', 'venv', '__pycache__',
        '.cache', 'coverage', 'vendor'
    )
    foreach ($segment in $segments) {
        if ($segment -in $skipSegments) {
            $kind = if ($segment -eq 'vendor') { 'vendor-root' } else { 'cache-root' }
            return [pscustomobject][ordered]@{
                root         = $segment
                kind         = $kind
                source       = 'path-segment-rule'
                auto_promote = $false
                walk_depth   = 0
                priority     = 110
            }
        }
    }
    return $null
}

function Get-McProjectRootPolicyForPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [AllowNull()]
        [object[]]$Policies
    )

    $actual = ConvertTo-McActualPath -Path $Path
    $normalized = ConvertTo-McNormalizedPath -Path $actual -ResolveExisting
    if ($null -eq $Policies) {
        $Policies = @(Get-McProjectRootPolicies -RepoRoot (Get-McRepoRoot -Path $PSScriptRoot))
    }

    $segmentPolicy = Get-McProjectPathSegmentPolicy -Path $actual
    if ($null -ne $segmentPolicy) {
        return $segmentPolicy
    }

    foreach ($policy in @($Policies | Sort-Object @{ Expression = { ([string]$_.root).Length }; Descending = $true }, @{ Expression = { [int]$_.priority }; Descending = $true })) {
        if (Test-McPathWithinRoot -Path $normalized -Root ([string]$policy.root)) {
            return $policy
        }
    }

    return [pscustomobject][ordered]@{
        root         = $null
        kind         = 'unknown-root'
        source       = 'no-root-policy'
        auto_promote = $false
        walk_depth   = 0
        priority     = 0
    }
}

function Get-McProjectSearchRoots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $roots = [System.Collections.Generic.List[string]]::new()
    foreach ($policy in @(Get-McProjectRootPolicies -RepoRoot $RepoRoot)) {
        if ([string]$policy.kind -notin @('project-root', 'workspace-root', 'developer-root', 'canonical-project')) {
            continue
        }
        $actual = ConvertTo-McActualPath -Path ([string]$policy.root)
        if (Test-Path -LiteralPath $actual -PathType Container -ErrorAction SilentlyContinue) {
            [void]$roots.Add($actual)
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
    $workspaceRefs = [System.Collections.Generic.List[string]]::new()
    $commands = [ordered]@{}
    $packageManager = $null
    $packageName = $null

    $packageJson = Join-Path $Path 'package.json'
    if (Test-Path -LiteralPath $packageJson -PathType Leaf -ErrorAction SilentlyContinue) {
        [void]$manifests.Add([pscustomobject][ordered]@{ path = ConvertTo-McNormalizedPath -Path $packageJson; kind = 'package-manifest' })
        try {
            $package = Read-McJson -Path $packageJson
            $declaredName = Get-McOptionalProperty -InputObject $package -Name 'name'
            if ($declaredName -is [string] -and $declaredName.Length -le 200 -and $declaredName -match '^[A-Za-z0-9@._/-]+$' -and (Test-McPrivacySafeText -Text $declaredName)) {
                $packageName = $declaredName.Trim()
            }
            $declared = Get-McOptionalProperty -InputObject $package -Name 'packageManager'
            if (-not [string]::IsNullOrWhiteSpace([string]$declared) -and (Test-McPrivacySafeText -Text ([string]$declared))) {
                $packageManager = ([string]$declared).Trim()
                $managerName = ($packageManager -replace '^@(?<scope>[^/]+)/', '@${scope}/' -split '@(?=\d)' | Select-Object -First 1)
                if (-not [string]::IsNullOrWhiteSpace($managerName)) { [void]$packageRefs.Add($managerName) }
            }

            if ($null -ne (Get-McOptionalProperty -InputObject $package -Name 'workspaces')) {
                [void]$workspaceRefs.Add('package-workspaces')
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

    $workspaceFiles = @(
        [pscustomobject]@{ name = 'pnpm-workspace.yaml'; manager = 'pnpm' },
        [pscustomobject]@{ name = 'lerna.json'; manager = 'npm-compatible' },
        [pscustomobject]@{ name = 'nx.json'; manager = 'npm-compatible' },
        [pscustomobject]@{ name = 'turbo.json'; manager = 'npm-compatible' }
    )
    foreach ($workspace in $workspaceFiles) {
        $workspacePath = Join-Path $Path $workspace.name
        if (Test-Path -LiteralPath $workspacePath -PathType Leaf -ErrorAction SilentlyContinue) {
            [void]$manifests.Add([pscustomobject][ordered]@{ path = ConvertTo-McNormalizedPath -Path $workspacePath; kind = 'workspace-metadata' })
            [void]$workspaceRefs.Add([string]$workspace.name)
            if ($workspace.manager -eq 'pnpm' -and [string]::IsNullOrWhiteSpace($packageManager)) {
                $packageManager = 'pnpm'
                [void]$packageRefs.Add('pnpm')
            }
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
        package_name = $packageName
        package_manager = $packageManager
        package_manager_refs = @($packageRefs | Sort-Object)
        workspace_refs = @($workspaceRefs | Sort-Object)
        runtime_refs = @($runtimeRefs | Sort-Object)
        manifests = @($manifests | Sort-Object path,kind)
        commands = [pscustomobject]$commands
    }
}

function Get-McProjectRepositoryNameHint {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Repository
    )

    if ([string]::IsNullOrWhiteSpace($Repository)) {
        return $null
    }
    $value = $Repository.TrimEnd('/')
    $leaf = ($value -split '/')[-1]
    if ($leaf.EndsWith('.git', [System.StringComparison]::OrdinalIgnoreCase)) {
        $leaf = $leaf.Substring(0, $leaf.Length - 4)
    }
    if ([string]::IsNullOrWhiteSpace($leaf)) {
        return $null
    }
    return $leaf
}

function Get-McProjectNameHint {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Repository,

        [AllowNull()]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$DirectoryName
    )

    $remoteName = Get-McProjectRepositoryNameHint -Repository $Repository
    if (-not [string]::IsNullOrWhiteSpace($remoteName)) {
        return [pscustomobject][ordered]@{ value = $remoteName; source = 'repository' }
    }
    if (-not [string]::IsNullOrWhiteSpace($PackageName)) {
        return [pscustomobject][ordered]@{ value = $PackageName; source = 'manifest' }
    }
    return [pscustomobject][ordered]@{ value = $DirectoryName; source = 'directory' }
}

function Get-McProjectCandidateAtPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [AllowNull()]
        [object]$RootPolicy,

        [AllowNull()]
        [object[]]$RootPolicies
    )

    $gitPath = Join-Path $Path '.git'
    $gitExists = Test-Path -LiteralPath $gitPath -ErrorAction SilentlyContinue
    $package = Get-McProjectPackageFingerprint -Path $Path
    $hasManifest = @($package.manifests).Count -gt 0
    if (-not $gitExists -and -not $hasManifest) {
        return $null
    }

    if ($null -eq $RootPolicy) {
        $RootPolicy = Get-McProjectRootPolicyForPath -Path $Path -Policies $RootPolicies
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
    $nameHint = Get-McProjectNameHint -Repository $remote -PackageName ([string]$package.package_name) -DirectoryName (Split-Path -Leaf $Path)
    $evidence = [System.Collections.Generic.List[object]]::new()
    if ($gitExists) {
        [void]$evidence.Add([pscustomobject][ordered]@{ type = 'git_fingerprint'; path = ConvertTo-McNormalizedPath -Path $gitPath })
    }
    foreach ($manifest in @($package.manifests)) {
        [void]$evidence.Add([pscustomobject][ordered]@{ type = 'manifest_present'; path = [string]$manifest.path; kind = [string]$manifest.kind })
    }
    [void]$evidence.Add([pscustomobject][ordered]@{
            type           = 'root_policy'
            classification = [string]$RootPolicy.kind
            source         = [string]$RootPolicy.source
            root           = [string]$RootPolicy.root
        })

    $observed = [ordered]@{
        local_path = $normalizedPath
        repository = $remote
        workspace_type = if ($gitExists -and $hasManifest) { 'git-project' } elseif ($gitExists) { 'git-repository' } else { 'manifest-project' }
        runtime_refs = @($package.runtime_refs)
        package_manager_refs = @($package.package_manager_refs)
        workspace_refs = @($package.workspace_refs)
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
        name_hint = [string]$nameHint.value
        name_source = [string]$nameHint.source
        path = $normalizedPath
        source = 'project-fingerprints'
        source_key = $normalizedPath
        confidence_hint = if ($gitExists) { 'high' } else { 'medium' }
        verified = [bool]$gitExists
        verification = if ($gitExists) { 'git-fingerprint' } else { 'manifest-only' }
        classification = [string]$RootPolicy.kind
        root_policy_source = [string]$RootPolicy.source
        promotion_eligible = [bool]($gitExists -and $RootPolicy.auto_promote)
        promotion_reason = if ($gitExists -and $RootPolicy.auto_promote) { 'verified-git-under-project-root' } elseif ($gitExists) { 'git-under-non-project-root' } else { 'manifest-only-candidate' }
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
        [int]$MaxDepth = 4,

        [ValidateRange(1, 1000)]
        [int]$MaxResults = 250
    )

    $candidates = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $rootPolicies = @(Get-McProjectRootPolicies -RepoRoot $RepoRoot)
    $skipNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('.git', '.open-next', '.vercel', '.turbo', '.dart_tool', '.gradle', '.idea', '.vs', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', 'node_modules', '.pnpm-store', '.yarn', '_npx', 'dist', 'build', 'out', 'target', '.next', '.nuxt', '.venv', 'venv', '__pycache__', '.cache', 'coverage', 'vendor')) {
        [void]$skipNames.Add($name)
    }

    foreach ($root in (Get-McProjectSearchRoots -RepoRoot $RepoRoot)) {
        $policy = Get-McProjectRootPolicyForPath -Path $root -Policies $rootPolicies
        [void]$queue.Enqueue([pscustomobject]@{ path = $root; depth = 0; scan_root = $root; max_depth = [Math]::Min($MaxDepth, [int]$policy.walk_depth) })
    }

    while ($queue.Count -gt 0 -and $candidates.Count -lt $MaxResults) {
        $item = $queue.Dequeue()
        $path = [string]$item.path
        try {
            $full = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path.TrimEnd('\')
            if (-not $visited.Add($full)) { continue }
            $attributes = (Get-Item -LiteralPath $full -ErrorAction Stop).Attributes
            if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }

            $policy = Get-McProjectRootPolicyForPath -Path $full -Policies $rootPolicies
            $candidate = Get-McProjectCandidateAtPath -Path $full -RootPolicy $policy -RootPolicies $rootPolicies
            if ($null -ne $candidate) {
                [void]$candidates.Add($candidate)
            }

            if ([int]$item.depth -ge [int]$item.max_depth) { continue }
            if ([string]$policy.kind -in @('tool-root', 'sdk-root', 'cache-root', 'vendor-root', 'unknown-root')) { continue }
            foreach ($child in @(Get-ChildItem -LiteralPath $full -Force -Directory -ErrorAction Stop)) {
                if ($skipNames.Contains($child.Name)) { continue }
                if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                $childPolicy = Get-McProjectRootPolicyForPath -Path $child.FullName -Policies $rootPolicies
                $childIsNewRoot = $null -ne $childPolicy.root -and ([string]$childPolicy.root).Equals((ConvertTo-McNormalizedPath -Path $child.FullName -ResolveExisting), [System.StringComparison]::OrdinalIgnoreCase)
                if ($childIsNewRoot) {
                    [void]$queue.Enqueue([pscustomobject]@{ path = $child.FullName; depth = 0; scan_root = $child.FullName; max_depth = [Math]::Min($MaxDepth, [int]$childPolicy.walk_depth) })
                }
                else {
                    [void]$queue.Enqueue([pscustomobject]@{ path = $child.FullName; depth = ([int]$item.depth + 1); scan_root = $item.scan_root; max_depth = [int]$item.max_depth })
                }
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
            continue
        }
        $existing = $dedupe[[string]$candidate.id]
        $candidateScore = if ($candidate.promotion_eligible -eq $true) { 4 } elseif ($candidate.verified -eq $true) { 3 } else { 1 }
        $existingScore = if ($existing.promotion_eligible -eq $true) { 4 } elseif ($existing.verified -eq $true) { 3 } else { 1 }
        if ($candidateScore -gt $existingScore) {
            $dedupe[[string]$candidate.id] = $candidate
        }
    }
    $items = @($dedupe.Values | Sort-Object id)
    $health = if ($warnings.Count -gt 0) { 'partial' } else { 'success' }
    return New-McProviderPayload -Value $items -Health $health -ResultCount $items.Count -Warnings @($warnings) -CoverageComplete $false
}
