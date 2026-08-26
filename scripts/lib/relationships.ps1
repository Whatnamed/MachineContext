Set-StrictMode -Version Latest

function Get-McRelationshipProperty {
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
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-McRelationshipPresent {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Entity
    )

    $observed = Get-McRelationshipProperty -InputObject $Entity -Name 'observed'
    if ((Get-McRelationshipProperty -InputObject $observed -Name 'present') -ne $true) {
        return $false
    }
    $verification = [string](Get-McRelationshipProperty -InputObject $observed -Name 'verification')
    return $verification -eq 'verified-present'
}

function Test-McRelationshipPathWithin {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Path,

        [AllowNull()]
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [string]::IsNullOrWhiteSpace($Root)) {
        return $false
    }
    $pathValue = (ConvertTo-McNormalizedPath -Path $Path).TrimEnd('\')
    $rootValue = (ConvertTo-McNormalizedPath -Path $Root).TrimEnd('\')
    return $pathValue.Equals($rootValue, [System.StringComparison]::OrdinalIgnoreCase) -or $pathValue.StartsWith($rootValue + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

function New-McStrongRelationship {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$From,

        [Parameter(Mandatory)]
        [string]$Relation,

        [Parameter(Mandatory)]
        [string]$To,

        [Parameter(Mandatory)]
        [ValidateSet('detected', 'inferred', 'curated')]
        [string]$Origin,

        [Parameter(Mandatory)]
        [object]$Evidence
    )

    return [pscustomobject][ordered]@{
        from     = $From
        relation = $Relation
        to       = $To
        origin   = $Origin
        evidence = @($Evidence)
    }
}

function Get-McStrongRelationships {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Observations
    )

    $relationships = [System.Collections.Generic.List[object]]::new()
    $software = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($moduleName in @('development', 'ai')) {
        foreach ($entity in @(Get-McRelationshipProperty -InputObject (Get-McRelationshipProperty -InputObject $Observations -Name 'software') -Name $moduleName)) {
            if ($null -ne $entity -and -not [string]::IsNullOrWhiteSpace([string]$entity.id)) {
                $software[[string]$entity.id] = $entity
            }
        }
    }

    # Git Bash is authoritative only when the dedicated provider observed the
    # shell under the verified Git installation root and the Git entity exists.
    $shells = Get-McRelationshipProperty -InputObject (Get-McRelationshipProperty -InputObject $Observations -Name 'machine') -Name 'shells'
    $gitBash = @($shells | Where-Object { [string]$_.id -eq 'shell-git-bash' } | Select-Object -First 1)
    if ($gitBash.Count -gt 0 -and $software.ContainsKey('git') -and (Test-McRelationshipPresent -Entity $gitBash[0]) -and (Test-McRelationshipPresent -Entity $software['git'])) {
        $bashGit = [string](Get-McRelationshipProperty -InputObject (Get-McRelationshipProperty -InputObject $gitBash[0] -Name 'observed') -Name 'git_executable')
        $bashRoot = [string](Get-McRelationshipProperty -InputObject (Get-McRelationshipProperty -InputObject $gitBash[0] -Name 'observed') -Name 'git_root')
        $gitExecutable = [string](Get-McRelationshipProperty -InputObject (Get-McRelationshipProperty -InputObject $software['git'] -Name 'observed') -Name 'executable')
        $gitRoot = [string](Get-McRelationshipProperty -InputObject (Get-McRelationshipProperty -InputObject (Get-McRelationshipProperty -InputObject $software['git'] -Name 'observed') -Name 'install') -Name 'root')
        if ((Test-McRelationshipPathWithin -Path $bashGit -Root $gitExecutable) -or (Test-McRelationshipPathWithin -Path $gitExecutable -Root $bashGit) -or (Test-McRelationshipPathWithin -Path $bashRoot -Root $gitRoot) -or (Test-McRelationshipPathWithin -Path $gitRoot -Root $bashRoot)) {
            [void]$relationships.Add((New-McStrongRelationship -From 'shell-git-bash' -Relation 'provided_by' -To 'git' -Origin 'detected' -Evidence ([pscustomobject][ordered]@{
                            provider = 'git-for-windows'
                            fields = @('git_root', 'git_executable', 'executable')
                        })))
        }
    }

    # Package managers installed beside a Node runtime are a strong path-based
    # relationship. Do not infer this for independent shims such as fallback
    # package-manager launchers.
    if ($software.ContainsKey('node') -and (Test-McRelationshipPresent -Entity $software['node'])) {
        $nodeObserved = Get-McRelationshipProperty -InputObject $software['node'] -Name 'observed'
        $nodeRoot = Get-McRelationshipProperty -InputObject (Get-McRelationshipProperty -InputObject $nodeObserved -Name 'install') -Name 'root'
        $nodeExecutable = Get-McRelationshipProperty -InputObject $nodeObserved -Name 'executable'
        foreach ($managerId in @('npm', 'pnpm', 'yarn')) {
            if (-not $software.ContainsKey($managerId) -or -not (Test-McRelationshipPresent -Entity $software[$managerId])) {
                continue
            }
            $managerObserved = Get-McRelationshipProperty -InputObject $software[$managerId] -Name 'observed'
            $managerExecutable = Get-McRelationshipProperty -InputObject $managerObserved -Name 'executable'
            $sameInstall = Test-McRelationshipPathWithin -Path ([string]$managerExecutable) -Root ([string]$nodeRoot)
            if (-not $sameInstall -and -not [string]::IsNullOrWhiteSpace([string]$nodeExecutable) -and -not [string]::IsNullOrWhiteSpace([string]$managerExecutable)) {
                $sameInstall = (Split-Path -Parent ([string]$managerExecutable)).Equals((Split-Path -Parent ([string]$nodeExecutable)), [System.StringComparison]::OrdinalIgnoreCase)
            }
            if ($sameInstall) {
                [void]$relationships.Add((New-McStrongRelationship -From $managerId -Relation 'provided_by' -To 'node' -Origin 'inferred' -Evidence ([pscustomobject][ordered]@{
                                provider = 'runtimes-package-managers-toolchain'
                                fields = @('executable', 'install.root')
                                paths = @([string]$managerExecutable, [string]$nodeExecutable)
                            })))
            }
        }
    }

    if ($software.ContainsKey('flutter') -and $software.ContainsKey('dart') -and (Test-McRelationshipPresent -Entity $software['flutter']) -and (Test-McRelationshipPresent -Entity $software['dart'])) {
        $flutterObserved = Get-McRelationshipProperty -InputObject $software['flutter'] -Name 'observed'
        $dartObserved = Get-McRelationshipProperty -InputObject $software['dart'] -Name 'observed'
        $flutterRoot = Get-McRelationshipProperty -InputObject (Get-McRelationshipProperty -InputObject $flutterObserved -Name 'install') -Name 'root'
        $dartExecutable = [string](Get-McRelationshipProperty -InputObject $dartObserved -Name 'executable')
        if (Test-McRelationshipPathWithin -Path $dartExecutable -Root ([string]$flutterRoot)) {
            [void]$relationships.Add((New-McStrongRelationship -From 'dart' -Relation 'provided_by' -To 'flutter' -Origin 'inferred' -Evidence ([pscustomobject][ordered]@{
                            provider = 'runtimes-package-managers-toolchain'
                            fields = @('executable', 'install.root')
                            paths = @($dartExecutable, [string]$flutterRoot)
                        })))
        }
    }

    # Only project candidates that passed the promotion gate may create
    # canonical references. Manifest fingerprints provide direct evidence for
    # these dependency relationships; manifest-only/tool-root candidates stay
    # local and cannot create dangling canonical edges.
    foreach ($project in @(Get-McRelationshipProperty -InputObject $Observations -Name 'projects')) {
        if ($null -eq $project -or (Get-McRelationshipProperty -InputObject $project -Name 'verified') -ne $true -or (Get-McRelationshipProperty -InputObject $project -Name 'promotion_eligible') -ne $true) {
            continue
        }
        $projectId = [string]$project.id
        if ([string]::IsNullOrWhiteSpace($projectId)) {
            continue
        }
        $projectObserved = Get-McRelationshipProperty -InputObject $project -Name 'observed'
        $manifestPaths = @((Get-McRelationshipProperty -InputObject $projectObserved -Name 'manifests') | ForEach-Object { [string]$_.path })
        foreach ($runtimeId in @((Get-McRelationshipProperty -InputObject $projectObserved -Name 'runtime_refs'))) {
            $targetId = [string]$runtimeId
            if (-not $software.ContainsKey($targetId) -or -not (Test-McRelationshipPresent -Entity $software[$targetId])) {
                continue
            }
            [void]$relationships.Add((New-McStrongRelationship -From $projectId -Relation 'uses_runtime' -To $targetId -Origin 'detected' -Evidence ([pscustomobject][ordered]@{
                            provider = 'project-fingerprints'
                            fields = @('manifests', 'runtime_refs')
                            manifests = @($manifestPaths)
                        })))
        }
        foreach ($managerId in @((Get-McRelationshipProperty -InputObject $projectObserved -Name 'package_manager_refs'))) {
            $targetId = [string]$managerId
            if (-not $software.ContainsKey($targetId) -or -not (Test-McRelationshipPresent -Entity $software[$targetId])) {
                continue
            }
            [void]$relationships.Add((New-McStrongRelationship -From $projectId -Relation 'uses_package_manager' -To $targetId -Origin 'detected' -Evidence ([pscustomobject][ordered]@{
                            provider = 'project-fingerprints'
                            fields = @('manifests', 'package_manager_refs')
                            manifests = @($manifestPaths)
                        })))
        }
    }

    return @($relationships)
}
