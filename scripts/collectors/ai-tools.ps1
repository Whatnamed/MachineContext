Set-StrictMode -Version Latest

function Get-McAiDefinitions {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ id = 'codex'; name = 'Codex'; command = 'codex'; args = @('--version') },
        [pscustomobject]@{ id = 'dsh'; name = 'DSH'; command = 'dsh'; args = @('--version') },
        [pscustomobject]@{ id = 'agy'; name = 'Agy'; command = 'agy'; args = @('--version') },
        [pscustomobject]@{ id = 'claude-code'; name = 'Claude Code'; command = 'claude'; args = @('--version') },
        [pscustomobject]@{ id = 'gemini-cli'; name = 'Gemini CLI'; command = 'gemini'; args = @('--version') },
        [pscustomobject]@{ id = 'cursor-cli'; name = 'Cursor CLI'; command = 'cursor'; args = @('--version') },
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
                [pscustomobject]@{ id = 'codex-bridge-config'; path = Join-Path $userProfile '.config\openai-api-server-via-codex\config.toml'; kind = 'config-file' }
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

    foreach ($definition in (Get-McAiDefinitions)) {
        $commands = @(Get-McExecutableCandidates -Executable $definition.command)
        if ($commands.Count -eq 0) { continue }
        $primary = $commands[0]
        $probe = Invoke-McProbe -Executable $primary.path -Arguments @($definition.args) -Provider 'ai-tooling' -ProbeName ([string]$definition.id) -TimeoutMs 8000 -OutputCapBytes 8192
        if ($probe.status -ne 'success') {
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
            continue
        }

        $observed = [ordered]@{
            present = $true
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

    $codex = @($entities | Where-Object id -eq 'codex' | Select-Object -First 1)
    $authCheck = @($pathObservations | Where-Object id -eq 'codex-auth' | Select-Object -First 1)
    if ($codex.Count -gt 0 -and $authCheck.Count -gt 0 -and $authCheck[0].exists) {
        $codex[0].observed.config_paths = @([pscustomobject][ordered]@{
            path = $authCheck[0].path
            exists = $true
            kind = 'auth-file'
        })
    }

    return New-McProviderPayload -Value ([pscustomobject][ordered]@{
            entities = @($entities)
            candidates = @($candidates)
            path_observations = @($pathObservations)
            relationships = @($relationships)
        }) -Health 'success' -ResultCount ($entities.Count + $pathObservations.Count) -CoverageComplete $false
}
