[CmdletBinding()]
param(
    [string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
. (Join-Path $RepoRoot 'scripts\lib\runtime.ps1')
. (Join-Path $RepoRoot 'scripts\lib\reconcile.ps1')

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

Invoke-McTest -Name 'path and URL normalization' -Body {
    $userProfile = [Environment]::GetEnvironmentVariable('USERPROFILE')
    Assert-McTrue -Condition (-not [string]::IsNullOrWhiteSpace($userProfile)) -Message 'USERPROFILE must be available for path fixture'
    $normalized = ConvertTo-McNormalizedPath -Path (Join-Path $userProfile '中文\工具\')
    Assert-McEqual -Actual $normalized -Expected '%USERPROFILE%\中文\工具' -Message 'user path should be normalized without account name'
    $repository = ConvertTo-McSafeRepositoryIdentity -Remote 'https://user:password@github.com/Whatnamed/MachineContext.git?token=secret'
    Assert-McEqual -Actual $repository -Expected 'github.com/Whatnamed/MachineContext' -Message 'remote identity must remove credentials/query and .git'
    Assert-McTrue -Condition (Test-McSafeId -Id 'runtime-node.js') -Message 'stable IDs should accept safe generated IDs'
}

Invoke-McTest -Name 'privacy guardrails' -Body {
    Assert-McTrue -Condition (-not (Test-McPrivacySafeText -Text 'https://user:secret@example.test/repo')) -Message 'credential-bearing URL must be rejected'
    Assert-McTrue -Condition (-not (Test-McPrivacySafeText -Text 'api_key=not-for-commit')) -Message 'credential assignment must be rejected'
    Assert-McTrue -Condition (Test-McPrivacySafeText -Text '%USERPROFILE%\\.codex\\auth.json exists') -Message 'safe auth-file existence hint should be allowed'
}

Invoke-McTest -Name 'safe subprocess probe' -Body {
    $success = Invoke-McProbe -Executable 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-Command', 'Write-Output probe-ok') -Provider 'fixture' -ProbeName 'success' -TimeoutMs 5000
    Assert-McEqual -Actual $success.status -Expected 'success' -Message 'successful probe health'
    Assert-McEqual -Actual $success.exit_code -Expected 0 -Message 'successful probe exit code'
    Assert-McTrue -Condition ($success.stdout -match 'probe-ok') -Message 'probe stdout must be captured'

    $stderr = Invoke-McProbe -Executable 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-Command', "[Console]::Error.WriteLine('version-on-stderr')") -Provider 'fixture' -ProbeName 'stderr' -TimeoutMs 5000
    Assert-McEqual -Actual $stderr.status -Expected 'success' -Message 'stderr-only successful probe health'
    Assert-McTrue -Condition ($stderr.stderr -match 'version-on-stderr') -Message 'probe stderr must be captured'
    Assert-McEqual -Actual (Get-McProbeVersionText -Probe $stderr) -Expected 'version-on-stderr' -Message 'version parser must accept stderr'

    $missing = Invoke-McProbe -Executable 'mc-command-that-cannot-exist-9f3a2d.exe' -Arguments @('--version') -Provider 'fixture' -ProbeName 'missing' -TimeoutMs 5000
    Assert-McEqual -Actual $missing.status -Expected 'unavailable' -Message 'missing command must fail soft'

    $timeout = Invoke-McProbe -Executable 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-Command', 'Start-Sleep -Seconds 5') -Provider 'fixture' -ProbeName 'timeout' -TimeoutMs 250
    Assert-McEqual -Actual $timeout.status -Expected 'timed_out' -Message 'probe timeout status'
    Assert-McTrue -Condition $timeout.timed_out -Message 'timeout flag must be set'

    $capped = Invoke-McProbe -Executable 'pwsh.exe' -Arguments @('-NoLogo', '-NoProfile', '-Command', "Write-Output ('x' * 10000)") -Provider 'fixture' -ProbeName 'cap' -TimeoutMs 5000 -OutputCapBytes 1024
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
