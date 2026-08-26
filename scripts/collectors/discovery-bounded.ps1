Set-StrictMode -Version Latest

function Get-McDiscoveryToolPatterns {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject][ordered]@{ name = 'node'; kind = 'runtime'; file_names = @('node.exe') },
        [pscustomobject][ordered]@{ name = 'python'; kind = 'runtime'; file_names = @('python.exe', 'python3.exe') },
        [pscustomobject][ordered]@{ name = 'git'; kind = 'development-tool'; file_names = @('git.exe') },
        [pscustomobject][ordered]@{ name = 'codex'; kind = 'ai-tool'; file_names = @('codex.exe', 'codex.cmd', 'codex.ps1') },
        [pscustomobject][ordered]@{ name = 'supabase'; kind = 'development-tool'; file_names = @('supabase.exe', 'supabase.cmd') },
        [pscustomobject][ordered]@{ name = 'flutter'; kind = 'sdk-tool'; file_names = @('flutter.bat', 'flutter.exe') },
        [pscustomobject][ordered]@{ name = 'dart'; kind = 'sdk-tool'; file_names = @('dart.exe') },
        [pscustomobject][ordered]@{ name = 'adb'; kind = 'development-tool'; file_names = @('adb.exe') },
        [pscustomobject][ordered]@{ name = 'nvcc'; kind = 'development-tool'; file_names = @('nvcc.exe') },
        [pscustomobject][ordered]@{ name = 'vscode'; kind = 'ide-cli'; file_names = @('code.cmd', 'code.exe') },
        [pscustomobject][ordered]@{ name = 'cargo'; kind = 'package-manager'; file_names = @('cargo.exe') },
        [pscustomobject][ordered]@{ name = 'go'; kind = 'runtime'; file_names = @('go.exe') },
        [pscustomobject][ordered]@{ name = 'rustc'; kind = 'runtime'; file_names = @('rustc.exe') },
        [pscustomobject][ordered]@{ name = 'uv'; kind = 'package-manager'; file_names = @('uv.exe', 'uvx.exe') },
        [pscustomobject][ordered]@{ name = 'pnpm'; kind = 'package-manager'; file_names = @('pnpm.cmd', 'pnpm.exe') },
        [pscustomobject][ordered]@{ name = 'npm'; kind = 'package-manager'; file_names = @('npm.cmd', 'npm.exe') },
        [pscustomobject][ordered]@{ name = 'bun'; kind = 'runtime'; file_names = @('bun.exe') },
        [pscustomobject][ordered]@{ name = 'gh'; kind = 'development-tool'; file_names = @('gh.exe') },
        [pscustomobject][ordered]@{ name = 'docker'; kind = 'development-tool'; file_names = @('docker.exe') },
        [pscustomobject][ordered]@{ name = 'kubectl'; kind = 'development-tool'; file_names = @('kubectl.exe') }
    )
}

function Get-McDiscoveryToolPatternMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FileName
    )

    foreach ($pattern in @(Get-McDiscoveryToolPatterns)) {
        foreach ($name in @($pattern.file_names)) {
            if ($FileName.Equals([string]$name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $pattern
            }
        }
    }
    return $null
}

function Get-McDiscoverySearchRoots {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $roots = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $addRoot = {
        param(
            [AllowNull()]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Source,

            [int]$MaxDepth = 2
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return
        }
        $actual = ConvertTo-McActualPath -Path $Path
        if (-not (Test-Path -LiteralPath $actual -PathType Container -ErrorAction SilentlyContinue)) {
            return
        }
        try {
            $full = (Resolve-Path -LiteralPath $actual -ErrorAction Stop).Path.TrimEnd('\')
        }
        catch {
            return
        }
        if (-not $seen.Add($full)) {
            return
        }
        [void]$roots.Add([pscustomobject][ordered]@{
                path       = $full
                source     = $Source
                max_depth  = $MaxDepth
            })
    }

    foreach ($root in @(Get-McProjectSearchRoots -RepoRoot $RepoRoot)) {
        $policy = Get-McProjectRootPolicyForPath -Path $root -Policies @(Get-McProjectRootPolicies -RepoRoot $RepoRoot)
        $depth = if ([string]$policy.kind -eq 'developer-root') { 2 } elseif ([string]$policy.kind -eq 'workspace-root') { 2 } else { 3 }
        & $addRoot -Path $root -Source 'project-root-policy' -MaxDepth $depth
    }

    foreach ($policy in @(Get-McProjectRootPolicies -RepoRoot $RepoRoot)) {
        if ([string]$policy.kind -notin @('tool-root', 'sdk-root')) {
            continue
        }
        $depth = if ([string]$policy.kind -eq 'sdk-root') { 1 } else { 3 }
        & $addRoot -Path ([string]$policy.root) -Source ([string]$policy.source) -MaxDepth $depth
    }

    foreach ($root in @(
            [Environment]::GetEnvironmentVariable('ProgramFiles'),
            [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),
            (Join-Path ([Environment]::GetEnvironmentVariable('LOCALAPPDATA')) 'Programs')
        )) {
        & $addRoot -Path $root -Source 'standard-install-root' -MaxDepth 2
    }

    return @($roots | Sort-Object path)
}

function Get-McBoundedDiscoveryCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [ValidateRange(1, 8)]
        [int]$MaxDepth = 3,

        [ValidateRange(25, 2000)]
        [int]$MaxResults = 250,

        [ValidateRange(250, 30000)]
        [int]$MaxDurationMs = 7000
    )

    $started = [System.Diagnostics.Stopwatch]::StartNew()
    $candidates = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $roots = @(Get-McDiscoverySearchRoots -RepoRoot $RepoRoot)
    $policies = @(Get-McProjectRootPolicies -RepoRoot $RepoRoot)
    $skipNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('.git', '.open-next', '.vercel', '.turbo', '.dart_tool', '.gradle', '.idea', '.vs', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', 'node_modules', '.pnpm-store', '.yarn', '_npx', 'dist', 'build', 'out', 'target', '.next', '.nuxt', '.venv', 'venv', '__pycache__', '.cache', 'coverage', 'vendor')) {
        [void]$skipNames.Add($name)
    }

    foreach ($root in $roots) {
        $policy = Get-McProjectRootPolicyForPath -Path $root.path -Policies $policies
        $limit = [Math]::Min($MaxDepth, [int]$root.max_depth)
        [void]$queue.Enqueue([pscustomobject]@{ path = $root.path; depth = 0; max_depth = $limit; scan_root = $root.path; policy = $policy })
    }

    $timedOut = $false
    while ($queue.Count -gt 0 -and $candidates.Count -lt $MaxResults) {
        if ($started.ElapsedMilliseconds -ge $MaxDurationMs) {
            $timedOut = $true
            break
        }
        $item = $queue.Dequeue()
        $path = [string]$item.path
        try {
            $full = (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path.TrimEnd('\')
            if (-not $visited.Add($full)) {
                continue
            }
            $directory = Get-Item -LiteralPath $full -ErrorAction Stop
            if (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                continue
            }

            $policy = Get-McProjectRootPolicyForPath -Path $full -Policies $policies
            foreach ($file in @(Get-ChildItem -LiteralPath $full -Force -File -ErrorAction Stop | Select-Object -First 5000)) {
                if ($started.ElapsedMilliseconds -ge $MaxDurationMs -or $candidates.Count -ge $MaxResults) {
                    $timedOut = $started.ElapsedMilliseconds -ge $MaxDurationMs
                    break
                }
                $match = Get-McDiscoveryToolPatternMatch -FileName $file.Name
                if ($null -eq $match) {
                    continue
                }
                $normalized = ConvertTo-McNormalizedPath -Path $file.FullName -ResolveExisting
                if ([string]::IsNullOrWhiteSpace($normalized)) {
                    continue
                }
                [void]$candidates.Add([pscustomobject][ordered]@{
                        candidate_id       = New-McStableId -Kind 'bounded-tool' -Identity $normalized
                        kind_hint          = 'portable-tool'
                        name_hint          = [string]$match.name
                        path               = $normalized
                        source             = 'bounded-filesystem'
                        source_key        = $normalized
                        confidence_hint    = 'low'
                        verified           = $false
                        promotion_eligible = $false
                        classification     = [string]$policy.kind
                        root_policy_source = [string]$policy.source
                        evidence           = @([pscustomobject][ordered]@{
                                type           = 'filesystem_name_match'
                                file_name      = [string]$file.Name
                                classification = [string]$policy.kind
                                root           = [string]$policy.root
                            })
                    })
            }

            if ([int]$item.depth -ge [int]$item.max_depth -or [string]$policy.kind -in @('cache-root', 'vendor-root')) {
                continue
            }
            foreach ($child in @(Get-ChildItem -LiteralPath $full -Force -Directory -ErrorAction Stop)) {
                if ($started.ElapsedMilliseconds -ge $MaxDurationMs) {
                    $timedOut = $true
                    break
                }
                if ($skipNames.Contains($child.Name) -or ($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    continue
                }
                $childPolicy = Get-McProjectRootPolicyForPath -Path $child.FullName -Policies $policies
                if ([string]$childPolicy.kind -in @('cache-root', 'vendor-root')) {
                    continue
                }
                $childNormalized = ConvertTo-McNormalizedPath -Path $child.FullName -ResolveExisting
                $childIsNewRoot = $null -ne $childPolicy.root -and ([string]$childPolicy.root).Equals($childNormalized, [System.StringComparison]::OrdinalIgnoreCase)
                if ($childIsNewRoot) {
                    $childLimit = if ([string]$childPolicy.kind -eq 'sdk-root') { 1 } else { [Math]::Min($MaxDepth, 3) }
                    [void]$queue.Enqueue([pscustomobject]@{ path = $child.FullName; depth = 0; max_depth = $childLimit; scan_root = $child.FullName; policy = $childPolicy })
                }
                else {
                    [void]$queue.Enqueue([pscustomobject]@{ path = $child.FullName; depth = ([int]$item.depth + 1); max_depth = [int]$item.max_depth; scan_root = $item.scan_root; policy = $childPolicy })
                }
            }
        }
        catch {
            [void]$warnings.Add("bounded discovery path unavailable: $path")
        }
    }

    if ($timedOut) {
        [void]$warnings.Add("bounded discovery budget reached at ${MaxDurationMs}ms")
    }
    $health = if ($timedOut -and $candidates.Count -eq 0) { 'timed_out' } elseif ($warnings.Count -gt 0) { 'partial' } else { 'success' }
    $local = [pscustomobject][ordered]@{
        roots              = @($roots | ForEach-Object { ConvertTo-McNormalizedPath -Path $_.path })
        max_depth          = $MaxDepth
        max_results        = $MaxResults
        max_duration_ms    = $MaxDurationMs
        timed_out          = $timedOut
        visited_directories = $visited.Count
    }
    return New-McProviderPayload -Value @($candidates) -Health $health -ResultCount $candidates.Count -Warnings @($warnings) -CoverageComplete $false -Optional $true -Local $local
}
