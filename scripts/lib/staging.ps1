Set-StrictMode -Version Latest

function Get-McRepoRoot {
    [CmdletBinding()]
    param(
        [string]$Path = $PSScriptRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Repository path is required.'
    }

    $candidate = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    while ($true) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'machine-context.json') -PathType Leaf) {
            return $candidate
        }

        $parent = Split-Path -Parent -Path $candidate
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $candidate) {
            break
        }
        $candidate = $parent
    }

    throw "Could not find machine-context.json above: $Path"
}

function New-McRunContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [Parameter(Mandatory)]
        [ValidateSet('Quick', 'Discover', 'Enrich', 'Full')]
        [string]$Mode,

        [string]$LocalRoot
    )

    if ([string]::IsNullOrWhiteSpace($LocalRoot)) {
        $LocalRoot = Join-Path $RepoRoot '.local'
    }
    $localRoot = $LocalRoot
    $runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssfff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runRoot = Join-Path $localRoot (Join-Path 'staging' $runId)
    $proposedRoot = Join-Path $runRoot 'proposed'
    $proposedContext = Join-Path $proposedRoot 'context'

    [void](New-Item -ItemType Directory -Path $proposedContext -Force)
    [void](New-Item -ItemType Directory -Path (Join-Path $runRoot 'raw') -Force)

    return [pscustomobject][ordered]@{
        schema_version       = 1
        run_id               = $runId
        mode                 = $Mode
        repo_root            = $RepoRoot
        local_root           = $localRoot
        run_root             = $runRoot
        proposed_root        = $proposedRoot
        proposed_context     = $proposedContext
        proposed_current     = Join-Path $proposedRoot 'CURRENT.md'
        observations_path    = Join-Path $runRoot 'observations.json'
        candidates_path      = Join-Path $runRoot 'candidates.json'
        diagnostics_path     = Join-Path $runRoot 'diagnostics.json'
        local_diagnostics_path = Join-Path $runRoot 'local-diagnostics.json'
        state_path           = Join-Path $localRoot 'state.json'
        started_at           = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Copy-McCanonicalToStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RunContext
    )

    $source = Join-Path $RunContext.repo_root 'context'
    if (-not (Test-Path -LiteralPath $source -PathType Container)) {
        throw "Canonical context directory does not exist: $source"
    }

    Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $RunContext.proposed_context -Recurse -Force
    }

    # Canonical files copied into a proposal are normalized through the same
    # serializer as newly reconciled files, so validation does not depend on
    # historical whitespace/property ordering.
    Get-ChildItem -LiteralPath $RunContext.proposed_context -Recurse -File -Filter '*.json' -ErrorAction Stop | Where-Object { $_.Name -ne '_template.json' } | ForEach-Object {
        $document = Read-McJson -Path $_.FullName
        Write-McJson -Path $_.FullName -InputObject $document
    }
}

function Write-McLocalRunArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RunContext,

        [Parameter(Mandatory)]
        [object]$Observations,

        [Parameter(Mandatory)]
        [object]$Candidates,

        [Parameter(Mandatory)]
        [object]$Diagnostics,

        [AllowNull()]
        [object]$LocalDiagnostics
    )

    Write-McJson -Path $RunContext.observations_path -InputObject $Observations
    Write-McJson -Path $RunContext.candidates_path -InputObject $Candidates
    Write-McJson -Path $RunContext.diagnostics_path -InputObject $Diagnostics
    if ($null -eq $LocalDiagnostics) {
        $LocalDiagnostics = [pscustomobject][ordered]@{}
    }
    Write-McJson -Path $RunContext.local_diagnostics_path -InputObject $LocalDiagnostics
}

function Write-McLocalState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$RunContext,

        [Parameter(Mandatory)]
        [object]$Diagnostics
    )

    $existing = $null
    if (Test-Path -LiteralPath $RunContext.state_path -PathType Leaf) {
        try {
            $existing = Read-McJson -Path $RunContext.state_path
        }
        catch {
            $existing = $null
        }
    }

    $providerState = [ordered]@{}
    foreach ($provider in @($Diagnostics.providers | Sort-Object provider)) {
        $providerState[[string]$provider.provider] = [pscustomobject][ordered]@{
            last_checked_at = (Get-Date).ToUniversalTime().ToString('o')
            health          = [string]$provider.health
            duration_ms     = [math]::Round([double]$provider.duration_ms, 2)
            result_count    = [int]$provider.result_count
            warning_count   = [int]$provider.warning_count
        }
    }

    $state = [pscustomobject][ordered]@{
        schema_version     = 1
        last_run_id         = $RunContext.run_id
        last_mode           = $RunContext.mode
        last_checked_at     = (Get-Date).ToUniversalTime().ToString('o')
        providers           = $providerState
        previous_run_id     = if ($null -ne $existing) { $existing.last_run_id } else { $null }
    }
    Write-McJson -Path $RunContext.state_path -InputObject $state
}

function Get-McCanonicalManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    return Read-McJson -Path (Join-Path $RepoRoot 'machine-context.json')
}

function Get-McCanonicalRelativePaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $manifest = Get-McCanonicalManifest -RepoRoot $RepoRoot
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($property in $manifest.canonical.PSObject.Properties) {
        $value = [string]$property.Value
        if ($value.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase) -and -not $paths.Contains($value)) {
            [void]$paths.Add($value)
        }
    }

    return @($paths | Sort-Object)
}

function Get-McCanonicalFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$ContextRoot = (Join-Path $RepoRoot 'context')
    )

    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($relativePath in (Get-McCanonicalRelativePaths -RepoRoot $RepoRoot)) {
        $path = Join-Path $ContextRoot ($relativePath -replace '^context[\\/]', '')
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            [void]$files.Add($path)
        }
    }

    # Project records are additive files referenced by the project index.
    $projectRoot = Join-Path $ContextRoot 'projects'
    if (Test-Path -LiteralPath $projectRoot -PathType Container) {
        Get-ChildItem -LiteralPath $projectRoot -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ne '_template.json' -and $_.Name -ne 'index.json'
        } | ForEach-Object {
            [void]$files.Add($_.FullName)
        }
    }

    return @($files | Sort-Object -Unique)
}
