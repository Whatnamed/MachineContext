Set-StrictMode -Version Latest

function Get-McAiDefinitions {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ id = 'dsh'; name = 'DSH'; command = 'dsh'; args = @('--version') },
        [pscustomobject]@{
            id      = 'omp'
            name    = 'Oh My Pi'
            command = 'omp'
            args    = @('--version')
            # Long-term semantics confirmed by the user; install.root is not
            # listed here because it is derived from the resolved executable
            # at scan time (see Get-McAiToolObservations).
            install = [ordered]@{
                method      = 'standalone-binary'
                scope       = 'user'
                environment = 'windows-native'
            }
        },
        [pscustomobject]@{ id = 'agy'; name = 'Agy'; command = 'agy'; args = @('--version') },
        [pscustomobject]@{ id = 'claude-code'; name = 'Claude Code'; command = 'claude'; args = @('--version') },
        [pscustomobject]@{ id = 'gemini-cli'; name = 'Gemini CLI'; command = 'gemini'; args = @('--version') },
        [pscustomobject]@{ id = 'cursor-cli'; name = 'Cursor CLI'; command = 'cursor'; args = @('--version') },
        [pscustomobject]@{ id = 'opencodex'; name = 'OpenCodex'; command = 'opencodex'; args = @('--version') },
        [pscustomobject]@{ id = 'grok'; name = 'Grok Build CLI'; command = 'grok'; args = @('--version') },
        [pscustomobject]@{ id = 'windsurf-cli'; name = 'Windsurf CLI'; command = 'windsurf'; args = @('--version') }
    )
}

function Get-McSafeAiPathChecks {
    [CmdletBinding()]
    param()

    $checks = [System.Collections.Generic.List[object]]::new()
    $userProfile = [Environment]::GetEnvironmentVariable('USERPROFILE')
    if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
        foreach ($check in @(
                [pscustomobject]@{ id = 'codex-data'; path = Join-Path $userProfile '.codex'; kind = 'data' },
                [pscustomobject]@{ id = 'codex-auth'; path = Join-Path $userProfile '.codex\auth.json'; kind = 'auth-file' },
                [pscustomobject]@{ id = 'codex-visualizations'; path = Join-Path $userProfile '.codex\visualizations'; kind = 'data' },
                [pscustomobject]@{ id = 'dsh-data'; path = Join-Path $userProfile '.dsh'; kind = 'data' },
                [pscustomobject]@{ id = 'dsh-presets'; path = Join-Path $userProfile '.dsh\.agent-presets'; kind = 'config-directory' },
                [pscustomobject]@{ id = 'codex-bridge-config'; path = Join-Path $userProfile '.config\openai-api-server-via-codex\config.toml'; kind = 'config-file' },
                [pscustomobject]@{ id = 'omp-agent-root'; path = Join-Path $userProfile '.omp\agent'; kind = 'config-directory' },
                [pscustomobject]@{ id = 'omp-config'; path = Join-Path $userProfile '.omp\agent\config.yml'; kind = 'config-file' },
                [pscustomobject]@{ id = 'omp-models'; path = Join-Path $userProfile '.omp\agent\models.yml'; kind = 'config-file' },
                [pscustomobject]@{ id = 'omp-settings'; path = Join-Path $userProfile '.omp\agent\settings.json'; kind = 'config-file' },
                [pscustomobject]@{ id = 'omp-env'; path = Join-Path $userProfile '.omp\agent\.env'; kind = 'sensitive-env-file' },
                [pscustomobject]@{ id = 'omp-agent-db'; path = Join-Path $userProfile '.omp\agent\agent.db'; kind = 'auth-store' },
                [pscustomobject]@{ id = 'omp-history-db'; path = Join-Path $userProfile '.omp\agent\history.db'; kind = 'history-store' }
            )) {
            [void]$checks.Add($check)
        }
    }

    foreach ($check in @(
            [pscustomobject]@{ id = 'codex-bridge-project'; path = 'E:\Codex\CodexBridge'; kind = 'project-root' },
            [pscustomobject]@{ id = 'open-codex-config'; path = 'E:\OpenCodex'; kind = 'project-root' }
        )) {
        [void]$checks.Add($check)
    }

    return @($checks)
}

function Get-McAiToolObservations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot
    )

    $entities = [System.Collections.Generic.List[object]]::new()
    $candidates = [System.Collections.Generic.List[object]]::new()
    $relationships = [System.Collections.Generic.List[object]]::new()
    $verificationEvents = [System.Collections.Generic.List[object]]::new()
    $failureCount = 0

    foreach ($definition in (Get-McAiDefinitions)) {
        $commands = @(Get-McExecutableCandidates -Executable $definition.command)
        if ($commands.Count -eq 0) {
            [void]$verificationEvents.Add([pscustomobject][ordered]@{
                    module = 'ai'
                    id = [string]$definition.id
                    provider = 'ai-tooling'
                    verification = 'unverified'
                    reason = 'persistent-command-not-found'
                    source_key = [string]$definition.command
                })
            continue
        }
        $primary = $commands[0]
        $probe = Invoke-McProbe -Executable $primary.path -Arguments @($definition.args) -Provider 'ai-tooling' -ProbeName ([string]$definition.id) -TimeoutMs 8000 -OutputCapBytes 8192
        if ($probe.status -ne 'success') {
            $failureCount++
            [void]$candidates.Add([pscustomobject][ordered]@{
                candidate_id = New-McStableId -Kind 'ai-candidate' -Identity ("{0}|{1}" -f $definition.id, $primary.path)
                kind_hint = 'ai-tool'
                name_hint = [string]$definition.name
                path = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
                source = 'command'
                source_key = [string]$definition.command
                confidence_hint = 'low'
                evidence = @([pscustomobject][ordered]@{ type = 'command_resolves'; verifier_status = [string]$probe.status })
                })
            [void]$verificationEvents.Add([pscustomobject][ordered]@{
                    module = 'ai'
                    id = [string]$definition.id
                    provider = 'ai-tooling'
                    verification = 'unverified'
                    reason = [string]$probe.status
                    source_key = [string]$definition.command
                })
            continue
        }

        $observed = [ordered]@{
            present = $true
            verification = 'verified-present'
            version = Get-McProbeVersionText -Probe $probe
            executable = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
            command_resolution = @(
                foreach ($command in $commands) {
                    [pscustomobject][ordered]@{
                        executable = ConvertTo-McNormalizedPath -Path ([string]$command.path)
                        command_type = [string]$command.command_type
                    }
                }
            )
            evidence = @([pscustomobject][ordered]@{
                provider = 'command'
                provider_key = [string]$definition.command
                fields = @('present', 'version', 'executable', 'command_resolution')
                confidence = 'high'
            })
        }
        $install = Get-McCollectionProperty -InputObject $definition -Name 'install'
        if ($null -ne $install) {
            $installObservation = [ordered]@{}
            foreach ($entry in (Get-McPropertyEntries -InputObject $install)) {
                $installObservation[[string]$entry.Name] = $entry.Value
            }
            $installRoot = Split-Path -Parent ([string]$primary.path)
            if (-not [string]::IsNullOrWhiteSpace($installRoot)) {
                $installObservation['root'] = (ConvertTo-McNormalizedPath -Path $installRoot)
            }
            $observed['install'] = [pscustomobject]$installObservation
            $observed['evidence'] = @(
                $observed['evidence']
                [pscustomobject][ordered]@{
                    provider     = 'command'
                    provider_key = [string]$definition.command
                    fields       = @('install.root')
                    confidence   = 'high'
                }
                [pscustomobject][ordered]@{
                    provider     = 'user-confirmed'
                    provider_key = [string]$definition.id
                    fields       = @('install.method', 'install.scope', 'install.environment')
                    confidence   = 'high'
                }
            )
        }
        [void]$entities.Add([pscustomobject][ordered]@{
            id = [string]$definition.id
            kind = 'ai-tool'
            name = [string]$definition.name
            observed = [pscustomobject]$observed
        })
    }

    $pathObservations = [System.Collections.Generic.List[object]]::new()
    foreach ($check in (Get-McSafeAiPathChecks)) {
        $normalized = ConvertTo-McNormalizedPath -Path ([string]$check.path)
        $exists = Test-Path -LiteralPath ([string]$check.path) -ErrorAction SilentlyContinue
        [void]$pathObservations.Add([pscustomobject][ordered]@{
            id = [string]$check.id
            kind = [string]$check.kind
            path = $normalized
            exists = [bool]$exists
        })
    }

    foreach ($check in @($pathObservations | Where-Object exists -eq $true)) {
        [void]$candidates.Add([pscustomobject][ordered]@{
            candidate_id = New-McStableId -Kind 'ai-path-candidate' -Identity ([string]$check.id)
            kind_hint = 'ai-tooling'
            name_hint = [string]$check.id
            path = [string]$check.path
            source = 'config'
            source_key = [string]$check.id
            confidence_hint = 'low'
            evidence = @([pscustomobject][ordered]@{ type = 'config_present'; exists = $true })
        })
    }

    $health = if ($failureCount -gt 0) { 'partial' } else { 'success' }
    return New-McProviderPayload -Value ([pscustomobject][ordered]@{
            entities = @($entities)
            candidates = @($candidates)
            path_observations = @($pathObservations)
            relationships = @($relationships)
        }) -Health $health -ResultCount ($entities.Count + $pathObservations.Count) -CoverageComplete $false -VerificationEvents @($verificationEvents)
}
