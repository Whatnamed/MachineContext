Set-StrictMode -Version Latest

# Source-specific, per-field allowlisted AI configuration projections. Each
# projector reads the real config files on this machine and projects only
# allowlisted safe fields; unknown fields are dropped by default and recorded
# (names only) as unprojected_keys. Raw config content, credential values, and
# credential-named fields never reach the projection; credential fields
# survive only as environment-variable names (credentialEnvName /
# credential_env_names) or a credential_configured boolean.

function Get-McOmpConfigProfile {
    [CmdletBinding()]
    param(
        [string]$AgentRoot = (Join-Path $env:USERPROFILE '.omp\agent')
    )

    $configYml = Join-Path $AgentRoot 'config.yml'
    $modelsYml = Join-Path $AgentRoot 'models.yml'
    $settingsJson = Join-Path $AgentRoot 'settings.json'
    $hasConfig = Test-Path -LiteralPath $configYml -PathType Leaf
    $hasModels = Test-Path -LiteralPath $modelsYml -PathType Leaf
    if (-not $hasConfig -and -not $hasModels) { return $null }

    $redactions = [System.Collections.Generic.List[object]]::new()
    $envNames = [System.Collections.Generic.List[string]]::new()
    $unprojected = [System.Collections.Generic.List[string]]::new()
    $files = @(
        New-McConfigSourceFileRecord -Path $configYml -Format yaml -Role config
        New-McConfigSourceFileRecord -Path $modelsYml -Format yaml -Role model-catalog
        New-McConfigSourceFileRecord -Path $settingsJson -Format json -Role settings
        New-McConfigSourceFileRecord -Path (Join-Path $AgentRoot '.env') -Format env -Role sensitive-env-file
        New-McConfigSourceFileRecord -Path (Join-Path $AgentRoot 'agent.db') -Format sqlite -Role auth-state-store
        New-McConfigSourceFileRecord -Path (Join-Path $AgentRoot 'history.db') -Format sqlite -Role session-history-store
    )

    $projection = [ordered]@{}
    $evidence = [System.Collections.Generic.List[object]]::new()

    $modelAllowlist = [ordered]@{
        id            = 'scalar-leaf'
        name          = 'scalar-leaf'
        reasoning     = 'scalar-leaf'
        input         = 'scalar-leaf'
        tokenizer     = 'scalar-leaf'
        supportsTools = 'scalar-leaf'
        contextWindow = 'scalar-leaf'
        maxTokens     = 'scalar-leaf'
        thinking      = [ordered]@{
            mode           = 'scalar-leaf'
            efforts        = 'scalar-leaf'
            defaultLevel   = 'scalar-leaf'
            requiresEffort = 'scalar-leaf'
        }
        compat        = [ordered]@{
            supportsReasoningEffort = 'scalar-leaf'
        }
    }

    if ($hasConfig) {
        $config = Read-McConfigYaml -Path $configYml
        $configAllowlist = [ordered]@{
            shellPath            = 'scalar-leaf'
            defaultThinkingLevel = 'scalar-leaf'
            modelRoles           = 'scalars'
            # webSearchOrder is a scalar sequence today; a future nested
            # provider object would be rejected until explicitly allowlisted.
            providers            = 'scalars'
        }
        $configProjection = ConvertTo-McAllowlistedProjection -Value $config -Allowlist $configAllowlist -Path 'omp.config' -Redactions $Redactions
        if (@(Get-McPropertyEntries -InputObject $configProjection).Count -gt 0) {
            $projection['config'] = $configProjection
            [void]$evidence.Add([pscustomobject][ordered]@{
                provider    = 'config-profiles'
                source_path = (ConvertTo-McNormalizedPath -Path $configYml)
                fields      = @(@(Get-McPropertyEntries -InputObject $configProjection) | ForEach-Object { [string]$_.Name })
            })
        }
    }

    if ($hasModels) {
        $models = Read-McConfigYaml -Path $modelsYml
        $providers = Get-McCollectionProperty -InputObject $models -Name 'providers'
        $providerAllowlist = [ordered]@{
            api            = 'scalar-leaf'
            authHeader     = 'scalar-leaf'
            baseUrl        = 'safe-url'
            apiKey         = 'credential-env'
            apiKeyEnv      = 'credential-env'
            models         = $modelAllowlist
            modelOverrides = [ordered]@{ __items__ = $modelAllowlist }
        }
        $providersProjection = [ordered]@{}
        foreach ($providerEntry in (Get-McPropertyEntries -InputObject $providers)) {
            $providerPath = "omp.models.providers.{0}" -f $providerEntry.Name
            $providerProjection = ConvertTo-McAllowlistedProjection -Value $providerEntry.Value -Allowlist $providerAllowlist -Path $providerPath -Redactions $Redactions -UnprojectedKeys $unprojected -RecordUnprojectedKeys
            if ($null -ne $providerProjection) { $providersProjection[[string]$providerEntry.Name] = $providerProjection }
        }
        if (@(Get-McPropertyEntries -InputObject $providersProjection).Count -gt 0) {
            $projection['models'] = [ordered]@{ providers = $providersProjection }
            [void]$evidence.Add([pscustomobject][ordered]@{
                provider    = 'config-profiles'
                source_path = (ConvertTo-McNormalizedPath -Path $modelsYml)
                fields      = @(@(Get-McPropertyEntries -InputObject $providersProjection) | ForEach-Object { [string]$_.Name })
            })
        }
    }

    Get-McCredentialEnvNamesFromProjection -Value $projection -Names $envNames
    if ($unprojected.Count -gt 0) {
        $projection['unprojected_keys'] = @($unprojected | Sort-Object -Unique)
    }

    return (New-McConfigProfileRecord -Id 'omp-config' -Tool 'omp' -ConfigRoot (ConvertTo-McNormalizedPath -Path $AgentRoot) `
        -Files $files -Projection $projection -Redactions $Redactions -CredentialEnvNames @($envNames) `
        -WireVerification 'not-wire-verified' -Evidence $evidence)
}

function Get-McDshConfigProfile {
    [CmdletBinding()]
    param(
        [string]$ConfigRoot = (Join-Path $env:USERPROFILE '.dsh')
    )

    $settingsYaml = Join-Path $ConfigRoot 'settings.yaml'
    if (-not (Test-Path -LiteralPath $settingsYaml -PathType Leaf)) { return $null }

    $redactions = [System.Collections.Generic.List[object]]::new()
    $envNames = [System.Collections.Generic.List[string]]::new()
    $unprojected = [System.Collections.Generic.List[string]]::new()
    $presetsDir = Join-Path $ConfigRoot '.agent-presets'
    $files = @(
        New-McConfigSourceFileRecord -Path $settingsYaml -Format yaml -Role config
        New-McConfigSourceFileRecord -Path (Join-Path $ConfigRoot '.credentials.yaml') -Format yaml -Role credential-file
        New-McConfigSourceFileRecord -Path $presetsDir -Format other -Role agent-preset-directory
    )

    $settings = Read-McConfigYaml -Path $settingsYaml
    if ($null -eq $settings) { return $null }
    $projection = [ordered]@{}
    $evidence = [System.Collections.Generic.List[object]]::new()
    $projectedSections = [System.Collections.Generic.List[string]]::new()

    $defaultModelAllowlist = [ordered]@{
        provider = 'scalar-leaf'
        model    = 'scalar-leaf'
    }
    $modelAllowlist = [ordered]@{
        id               = 'scalar-leaf'
        name             = 'scalar-leaf'
        contextWindow    = 'scalar-leaf'
        maxTokens        = 'scalar-leaf'
        input            = 'scalar-leaf'
        reasoning        = 'scalar-leaf'
        reasoningEfforts = 'scalars'
    }
    $providerAllowlist = [ordered]@{
        displayName      = 'scalar-leaf'
        apiKeyEnv        = 'credential-env'
        apiKey           = 'credential-env'
        api              = 'scalar-leaf'
        baseURL          = 'safe-url'
        defaultInput     = 'scalar-leaf'
        defaultMaxTokens = 'scalar-leaf'
        models           = $modelAllowlist
    }

    foreach ($section in (Get-McPropertyEntries -InputObject $settings)) {
        $sectionName = [string]$section.Name
        $sectionPath = "dsh.{0}" -f $sectionName
        if ($sectionName -eq 'agent-default-model') {
            $sectionProjection = ConvertTo-McAllowlistedProjection -Value $section.Value -Allowlist $defaultModelAllowlist -Path $sectionPath -Redactions $Redactions
            if (@(Get-McPropertyEntries -InputObject $sectionProjection).Count -gt 0) {
                $projection[$sectionName] = $sectionProjection
                [void]$projectedSections.Add($sectionName)
            }
            continue
        }
        if ($sectionName -eq 'agent-presets') {
            # Preset roles map names to scalar values; the strict scalar
            # collection keeps nested objects out without an empty allowlist.
            $sectionProjection = ConvertTo-McScalarCollectionValue -Value $section.Value -Path $sectionPath -Redactions $Redactions
            if (@(Get-McPropertyEntries -InputObject $sectionProjection).Count -gt 0) {
                $projection[$sectionName] = $sectionProjection
                [void]$projectedSections.Add($sectionName)
            }
            continue
        }
        if (-not $sectionName.StartsWith('llm-')) { continue }
        $sectionProjection = $null
        $providers = Get-McCollectionProperty -InputObject $section.Value -Name 'providers'
        if ($null -ne $providers) {
            $providersProjection = [ordered]@{}
            foreach ($providerEntry in (Get-McPropertyEntries -InputObject $providers)) {
                $providerProjection = ConvertTo-McAllowlistedProjection -Value $providerEntry.Value -Allowlist $providerAllowlist -Path ("{0}.providers.{1}" -f $sectionPath, $providerEntry.Name) -Redactions $Redactions -UnprojectedKeys $unprojected -RecordUnprojectedKeys
                if ($null -ne $providerProjection) { $providersProjection[[string]$providerEntry.Name] = $providerProjection }
            }
            if (@(Get-McPropertyEntries -InputObject $providersProjection).Count -gt 0) {
                $sectionProjection = [ordered]@{ providers = $providersProjection }
            }
        }
        elseif ($null -ne (Get-McCollectionProperty -InputObject $section.Value -Name 'baseURL') -or $null -ne (Get-McCollectionProperty -InputObject $section.Value -Name 'models')) {
            $sectionProjection = ConvertTo-McAllowlistedProjection -Value $section.Value -Allowlist $providerAllowlist -Path $sectionPath -Redactions $Redactions -UnprojectedKeys $unprojected -RecordUnprojectedKeys
        }
        if ($null -ne $sectionProjection -and @(Get-McPropertyEntries -InputObject $sectionProjection).Count -gt 0) {
            $projection[$sectionName] = $sectionProjection
            [void]$projectedSections.Add($sectionName)
        }
        else {
            if (-not $projection.Contains('unprojected_sections')) { $projection['unprojected_sections'] = [System.Collections.Generic.List[string]]::new() }
            [void]$projection['unprojected_sections'].Add($sectionName)
        }
    }

    if (@(Get-McPropertyEntries -InputObject $projection).Count -gt 0) {
        [void]$evidence.Add([pscustomobject][ordered]@{
            provider    = 'config-profiles'
            source_path = (ConvertTo-McNormalizedPath -Path $settingsYaml)
            fields      = @($projectedSections)
        })
    }

    if ($projection.Contains('unprojected_sections')) {
        $projection['unprojected_sections'] = @($projection['unprojected_sections'])
    }

    $presetNames = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $presetsDir -PathType Container) {
        foreach ($presetDir in @(Get-ChildItem -LiteralPath $presetsDir -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
            $presetYml = Join-Path $presetDir.FullName 'preset.yml'
            $presetName = $presetDir.Name
            if (Test-Path -LiteralPath $presetYml -PathType Leaf) {
                try {
                    $preset = Read-McConfigYaml -Path $presetYml
                    $declared = Get-McCollectionProperty -InputObject $preset -Name 'name'
                    if (-not [string]::IsNullOrWhiteSpace([string]$declared)) { $presetName = [string]$declared }
                }
                catch {
                }
            }
            [void]$presetNames.Add([pscustomobject][ordered]@{
                name = $presetName
                path = (ConvertTo-McNormalizedPath -Path $presetDir.FullName)
            })
        }
    }
    if ($presetNames.Count -gt 0) { $projection['agent_presets'] = @($presetNames) }

    Get-McCredentialEnvNamesFromProjection -Value $projection -Names $envNames
    if ($unprojected.Count -gt 0) {
        $projection['unprojected_keys'] = @($unprojected | Sort-Object -Unique)
    }

    return (New-McConfigProfileRecord -Id 'dsh-config' -Tool 'dsh' -ConfigRoot (ConvertTo-McNormalizedPath -Path $ConfigRoot) `
        -Files $files -Projection $projection -Redactions $Redactions -CredentialEnvNames @($envNames) `
        -WireVerification 'not-wire-verified' -Evidence $evidence)
}

function Get-McZcodeConfigProfile {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$AppDataRoot = 'D:\ZCode\appdata\.zcode\v2',

        [AllowNull()]
        [string]$UserProfileRoot = (Join-Path $env:USERPROFILE '.zcode\v2')
    )

    # The appdata config.json is the only active source. A userprofile copy is
    # recorded (path/exists only) but is never parsed or promoted, so removing
    # the active config can never silently resurrect the stale sensitive copy.
    $primaryConfig = $null
    $hasPrimary = $false
    if (-not [string]::IsNullOrWhiteSpace($AppDataRoot)) {
        $primaryConfig = Join-Path $AppDataRoot 'config.json'
        $hasPrimary = Test-Path -LiteralPath $primaryConfig -PathType Leaf
    }
    if (-not $hasPrimary) { return $null }
    $secondaryConfig = $null
    $hasSecondary = $false
    if (-not [string]::IsNullOrWhiteSpace($UserProfileRoot)) {
        $secondaryConfig = Join-Path $UserProfileRoot 'config.json'
        $hasSecondary = Test-Path -LiteralPath $secondaryConfig -PathType Leaf
    }

    $redactions = [System.Collections.Generic.List[object]]::new()
    $files = [System.Collections.Generic.List[object]]::new()
    [void]$files.Add((New-McConfigSourceFileRecord -Path $primaryConfig -Format json -Role config))
    if ($hasSecondary) { [void]$files.Add((New-McConfigSourceFileRecord -Path $secondaryConfig -Format json -Role sensitive-config-copy)) }
    if (-not [string]::IsNullOrWhiteSpace($UserProfileRoot)) {
        [void]$files.Add((New-McConfigSourceFileRecord -Path (Join-Path $UserProfileRoot 'setting.json') -Format json -Role settings))
    }
    [void]$files.Add((New-McConfigSourceFileRecord -Path (Join-Path $AppDataRoot 'bot-config.json') -Format json -Role bot-config))
    [void]$files.Add((New-McConfigSourceFileRecord -Path (Join-Path $AppDataRoot 'credentials.json') -Format json -Role credential-store))
    $files = @($files)

    $projection = [ordered]@{}
    $evidence = [System.Collections.Generic.List[object]]::new()
    $config = Read-McJson -Path $primaryConfig
    $providers = Get-McCollectionProperty -InputObject $config -Name 'provider'

    $providersProjection = [ordered]@{}
    foreach ($providerEntry in (Get-McPropertyEntries -InputObject $providers)) {
        $provider = $providerEntry.Value
        $providerProjection = [ordered]@{}
        foreach ($name in @('name', 'kind', 'enabled', 'source')) {
            $value = Get-McCollectionProperty -InputObject $provider -Name $name
            if ($null -ne $value) { $providerProjection[$name] = $value }
        }
        $options = Get-McCollectionProperty -InputObject $provider -Name 'options'
        $baseUrl = ConvertTo-McProjectionSafeUrl -Url ([string](Get-McCollectionProperty -InputObject $options -Name 'baseURL')) -Redactions $Redactions -Path ("zcode.providers.{0}.options.baseURL" -f $providerEntry.Name)
        if (-not [string]::IsNullOrWhiteSpace($baseUrl)) { $providerProjection['baseURL'] = $baseUrl }
        $apiKey = Get-McCollectionProperty -InputObject $options -Name 'apiKey'
        if (-not [string]::IsNullOrWhiteSpace([string]$apiKey)) {
            $providerProjection['credential_configured'] = $true
            Add-McProjectionRedaction -Redactions $Redactions -Path ("zcode.providers.{0}.options.apiKey" -f $providerEntry.Name) -Reason 'credential-value'
        }
        $models = Get-McCollectionProperty -InputObject $provider -Name 'models'
        $modelsProjection = [ordered]@{}
        foreach ($modelEntry in (Get-McPropertyEntries -InputObject $models)) {
            $model = $modelEntry.Value
            $modelProjection = [ordered]@{}
            $modelName = Get-McCollectionProperty -InputObject $model -Name 'name'
            if (-not [string]::IsNullOrWhiteSpace([string]$modelName)) { $modelProjection['name'] = [string]$modelName }
            foreach ($sectionName in @('reasoning', 'limit', 'modalities')) {
                $section = Get-McCollectionProperty -InputObject $model -Name $sectionName
                if ($null -eq $section) { continue }
                $sectionProjection = [ordered]@{}
                foreach ($entry in (Get-McPropertyEntries -InputObject $section)) {
                    $projected = ConvertTo-McSafeProjectionValue -Value $entry.Value -Path ("zcode.providers.{0}.models.{1}.{2}.{3}" -f $providerEntry.Name, $modelEntry.Name, $sectionName, $entry.Name) -Redactions $Redactions
                    if ($null -ne $projected) { $sectionProjection[[string]$entry.Name] = $projected }
                }
                if (@(Get-McPropertyEntries -InputObject $sectionProjection).Count -gt 0) { $modelProjection[$sectionName] = $sectionProjection }
            }
            if (@(Get-McPropertyEntries -InputObject $modelProjection).Count -gt 0) { $modelsProjection[[string]$modelEntry.Name] = $modelProjection }
        }
        if (@(Get-McPropertyEntries -InputObject $modelsProjection).Count -gt 0) { $providerProjection['models'] = $modelsProjection }
        $providersProjection[[string]$providerEntry.Name] = $providerProjection
    }
    if (@(Get-McPropertyEntries -InputObject $providersProjection).Count -gt 0) {
        $projection['providers'] = $providersProjection
        [void]$evidence.Add([pscustomobject][ordered]@{
            provider    = 'config-profiles'
            source_path = (ConvertTo-McNormalizedPath -Path $primaryConfig)
            fields      = @('providers')
        })
    }

    if (-not [string]::IsNullOrWhiteSpace($UserProfileRoot)) {
        $settingPath = Join-Path $UserProfileRoot 'setting.json'
        if (Test-Path -LiteralPath $settingPath -PathType Leaf) {
            try {
                $settings = Read-McJson -Path $settingPath
                $selection = [ordered]@{}
                foreach ($name in @('modelProviderFamilyModes', 'modelProviderFamilySelectedKeys', 'enabledBuiltinAgentCliProviders')) {
                    $value = Get-McCollectionProperty -InputObject $settings -Name $name
                    if ($null -ne $value) { $selection[$name] = (ConvertTo-McSafeProjectionValue -Value $value -Path ("zcode.settings.{0}" -f $name) -Redactions $Redactions) }
                }
                if (@(Get-McPropertyEntries -InputObject $selection).Count -gt 0) {
                    $projection['selection'] = $selection
                    [void]$evidence.Add([pscustomobject][ordered]@{
                        provider    = 'config-profiles'
                        source_path = (ConvertTo-McNormalizedPath -Path $settingPath)
                        fields      = @(@(Get-McPropertyEntries -InputObject $selection) | ForEach-Object { [string]$_.Name })
                    })
                }
            }
            catch {
                Add-McProjectionRedaction -Redactions $Redactions -Path 'zcode.settings' -Reason 'unparseable-source'
            }
        }
    }

    $botConfigPath = Join-Path $AppDataRoot 'bot-config.json'
    if (Test-Path -LiteralPath $botConfigPath -PathType Leaf) {
        try {
            $botConfig = Read-McJson -Path $botConfigPath
            $bots = @(Get-McCollectionProperty -InputObject $botConfig -Name 'bots') | ForEach-Object {
                [ordered]@{
                    name     = [string](Get-McCollectionProperty -InputObject $_ -Name 'name')
                    provider = [string](Get-McCollectionProperty -InputObject $_ -Name 'provider')
                    enabled  = [bool](Get-McCollectionProperty -InputObject $_ -Name 'enabled')
                }
            }
            if ($bots.Count -gt 0) {
                $projection['bots'] = @($bots)
                [void]$evidence.Add([pscustomobject][ordered]@{
                    provider    = 'config-profiles'
                    source_path = (ConvertTo-McNormalizedPath -Path $botConfigPath)
                    fields      = @('bots')
                })
            }
        }
        catch {
            Add-McProjectionRedaction -Redactions $Redactions -Path 'zcode.bots' -Reason 'unparseable-source'
        }
    }

    return (New-McConfigProfileRecord -Id 'zcode-config' -Tool 'zcode' -ConfigRoot (ConvertTo-McNormalizedPath -Path $AppDataRoot) `
        -Files $files -Projection $projection -Redactions $Redactions `
        -WireVerification 'not-wire-verified' -Evidence $evidence)
}

function Get-McOpencodexConfigProfile {
    [CmdletBinding()]
    param(
        [string]$ConfigRoot = (Join-Path $env:USERPROFILE '.opencodex')
    )

    $configPath = Join-Path $ConfigRoot 'config.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { return $null }

    $redactions = [System.Collections.Generic.List[object]]::new()
    $unprojected = [System.Collections.Generic.List[string]]::new()
    $files = @(
        New-McConfigSourceFileRecord -Path $configPath -Format json -Role config
        New-McConfigSourceFileRecord -Path (Join-Path $ConfigRoot 'auth.json') -Format json -Role credential-file
        New-McConfigSourceFileRecord -Path (Join-Path $ConfigRoot 'codex-accounts.json') -Format json -Role credential-file
        New-McConfigSourceFileRecord -Path (Join-Path $ConfigRoot 'admin-api-token') -Format other -Role credential-file
        New-McConfigSourceFileRecord -Path (Join-Path $ConfigRoot 'usage.jsonl') -Format other -Role usage-log
        New-McConfigSourceFileRecord -Path (Join-Path $ConfigRoot 'routing-history.sqlite') -Format sqlite -Role routing-history-store
    )

    $config = Read-McJson -Path $configPath
    $projection = [ordered]@{}
    $evidence = [System.Collections.Generic.List[object]]::new()

    $topAllowlist = [ordered]@{
        port                = 'scalar-leaf'
        defaultProvider     = 'scalar-leaf'
        contextCapValue     = 'scalar-leaf'
        providerContextCaps = 'scalars'
        clientIntegrations  = 'scalars'
        websockets          = 'scalar-leaf'
        codexAutoStart      = 'scalar-leaf'
        subagentModels      = 'scalar-leaf'
        disabledModels      = 'scalar-leaf'
    }
    $topProjection = ConvertTo-McAllowlistedProjection -Value $config -Allowlist $topAllowlist -Path 'opencodex' -Redactions $Redactions
    foreach ($entry in (Get-McPropertyEntries -InputObject $topProjection)) {
        $projection[[string]$entry.Name] = $entry.Value
    }

    $claudeCode = Get-McCollectionProperty -InputObject $config -Name 'claudeCode'
    if ($null -ne $claudeCode) {
        $claudeAllowlist = [ordered]@{
            enabled  = 'scalar-leaf'
            authMode = 'scalar-leaf'
            desktopProfile = [ordered]@{
                defaults = 'scalars'
            }
        }
        $claudeProjection = ConvertTo-McAllowlistedProjection -Value $claudeCode -Allowlist $claudeAllowlist -Path 'opencodex.claudeCode' -Redactions $Redactions
        if (@(Get-McPropertyEntries -InputObject $claudeProjection).Count -gt 0) {
            $projection['claudeCode'] = $claudeProjection
        }
    }

    $sidecarAllowlist = [ordered]@{
        backend   = 'scalar-leaf'
        model     = 'scalar-leaf'
        reasoning = 'scalar-leaf'
    }
    foreach ($sidecarName in @('webSearchSidecar', 'visionSidecar')) {
        $sidecar = Get-McCollectionProperty -InputObject $config -Name $sidecarName
        if ($null -eq $sidecar) { continue }
        $sidecarProjection = ConvertTo-McAllowlistedProjection -Value $sidecar -Allowlist $sidecarAllowlist -Path ("opencodex.{0}" -f $sidecarName) -Redactions $Redactions
        if (@(Get-McPropertyEntries -InputObject $sidecarProjection).Count -gt 0) { $projection[$sidecarName] = $sidecarProjection }
    }

    $providers = Get-McCollectionProperty -InputObject $config -Name 'providers'
    $providerAllowlist = [ordered]@{
        adapter                       = 'scalar-leaf'
        allowPrivateNetwork           = 'scalar-leaf'
        authMode                      = 'scalar-leaf'
        baseUrl                       = 'safe-url'
        codexAccountMode              = 'scalar-leaf'
        contextWindow                 = 'scalar-leaf'
        defaultModel                  = 'scalar-leaf'
        liveModels                    = 'scalar-leaf'
        localCompactionAdapter        = 'scalar-leaf'
        modelContextWindows           = 'scalars'
        modelReasoningEfforts         = 'scalars'
        modelReasoningEffortMap       = [ordered]@{ __items__ = 'scalars' }
        models                        = 'scalar-leaf'
        noVisionModels                = 'scalar-leaf'
        preserveReasoningContentModels = 'scalar-leaf'
        responsesPath                 = 'scalar-leaf'
        statelessResponses            = 'scalar-leaf'
        apiKey                        = 'credential-configured'
        apiKeyPool                    = 'credential-configured'
        apiKeys                       = 'credential-configured'
    }
    $providersProjection = [ordered]@{}
    foreach ($providerEntry in (Get-McPropertyEntries -InputObject $providers)) {
        $providerProjection = ConvertTo-McAllowlistedProjection -Value $providerEntry.Value -Allowlist $providerAllowlist -Path ("opencodex.providers.{0}" -f $providerEntry.Name) -Redactions $Redactions -UnprojectedKeys $unprojected -RecordUnprojectedKeys
        if ($null -ne $providerProjection) { $providersProjection[[string]$providerEntry.Name] = $providerProjection }
    }
    if (@(Get-McPropertyEntries -InputObject $providersProjection).Count -gt 0) {
        $projection['providers'] = $providersProjection
    }

    if ($unprojected.Count -gt 0) {
        $projection['unprojected_keys'] = @($unprojected | Sort-Object -Unique)
    }

    [void]$evidence.Add([pscustomobject][ordered]@{
        provider    = 'config-profiles'
        source_path = (ConvertTo-McNormalizedPath -Path $configPath)
        fields      = @(@(Get-McPropertyEntries -InputObject $projection) | ForEach-Object { [string]$_.Name })
    })

    return (New-McConfigProfileRecord -Id 'opencodex-config' -Tool 'opencodex' -ConfigRoot (ConvertTo-McNormalizedPath -Path $ConfigRoot) `
        -Files $files -Projection $projection -Redactions $Redactions `
        -WireVerification 'not-wire-verified' -Evidence $evidence)
}

function Get-McCodexConfigProfile {
    [CmdletBinding()]
    param(
        [string]$ConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml')
    )

    # The Codex CLI and the Codex desktop app share this file (CODEX_HOME);
    # only top-level scalar settings are projected. [mcp_servers.*] tables are
    # owned by the MCP inventory and auth.json is recorded as existence only.
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $null }

    $redactions = [System.Collections.Generic.List[object]]::new()
    $unprojected = [System.Collections.Generic.List[string]]::new()
    $configRoot = Split-Path -Parent $ConfigPath
    $files = @(
        New-McConfigSourceFileRecord -Path $ConfigPath -Format toml -Role config
        New-McConfigSourceFileRecord -Path (Join-Path $configRoot 'auth.json') -Format json -Role credential-file
    )

    $topLevel = Get-McTomlTopLevelScalars -Text ([System.IO.File]::ReadAllText($ConfigPath))
    $allowlist = [ordered]@{
        model                          = 'scalar-leaf'
        sandbox_mode                   = 'scalar-leaf'
        model_reasoning_effort         = 'scalar-leaf'
        model_context_window           = 'scalar-leaf'
        model_auto_compact_token_limit = 'scalar-leaf'
    }
    $projection = ConvertTo-McAllowlistedProjection -Value $topLevel -Allowlist $allowlist -Path 'codex-cli' -Redactions $Redactions -UnprojectedKeys $unprojected -RecordUnprojectedKeys
    if ($unprojected.Count -gt 0) { $projection['unprojected_keys'] = @($unprojected | Sort-Object -Unique) }

    $evidence = @([pscustomobject][ordered]@{
        provider    = 'config-profiles'
        source_path = (ConvertTo-McNormalizedPath -Path $ConfigPath)
        fields      = @(@(Get-McPropertyEntries -InputObject $projection) | ForEach-Object { [string]$_.Name })
    })

    return (New-McConfigProfileRecord -Id 'codex-cli-config' -Tool 'codex-cli' -ConfigRoot (ConvertTo-McNormalizedPath -Path $configRoot) `
        -Files $files -Projection $projection -Redactions $Redactions `
        -WireVerification 'not-wire-verified' -Evidence $evidence)
}

function Get-McMcpInventoryRecord {
    [CmdletBinding()]
    param(
        [string]$ClaudeConfigPath = (Join-Path $env:USERPROFILE '.claude.json'),
        [string]$GeminiSettingsPath = (Join-Path $env:USERPROFILE '.gemini\settings.json'),
        [string]$CodexConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'),
        [string]$CursorMcpPath = (Join-Path $env:USERPROFILE '.cursor\mcp.json')
    )

    $redactions = [System.Collections.Generic.List[object]]::new()
    $servers = [System.Collections.Generic.List[object]]::new()

    function Add-McMcpServer {
        param([string]$Tool, [string]$Scope, [string]$Name, [object]$Definition)

        $transport = [string](Get-McCollectionProperty -InputObject $Definition -Name 'type')
        if ([string]::IsNullOrWhiteSpace($transport)) { $transport = 'stdio' }
        $server = [ordered]@{
            tool      = $Tool
            scope     = $Scope
            name      = $Name
            transport = $transport
        }
        $command = Get-McCollectionProperty -InputObject $Definition -Name 'command'
        if (-not [string]::IsNullOrWhiteSpace([string]$command)) { $server['command'] = (ConvertTo-McNormalizedPath -Path ([string]$command)) }
        $url = ConvertTo-McProjectionSafeUrl -Url ([string](Get-McCollectionProperty -InputObject $Definition -Name 'url')) -Redactions $Redactions -Path ("mcp.{0}.{1}.url" -f $Tool, $Name)
        if (-not [string]::IsNullOrWhiteSpace($url)) { $server['url'] = $url }
        $args = @(Get-McCollectionProperty -InputObject $Definition -Name 'args')
        if ($args.Count -gt 0) {
            $safeArgs = Get-McSafeMcpArguments -Arguments $args -Redactions $Redactions -Path ("mcp.{0}.{1}.args" -f $Tool, $Name)
            if (@($safeArgs).Count -gt 0) { $server['args'] = @($safeArgs) }
        }
        $env = Get-McCollectionProperty -InputObject $Definition -Name 'env'
        $envNames = @(Get-McPropertyEntries -InputObject $env | ForEach-Object { [string]$_.Name })
        if ($envNames.Count -gt 0) { $server['env_names'] = @($envNames | Sort-Object) }
        [void]$servers.Add([pscustomobject]$server)
    }

    $files = [System.Collections.Generic.List[object]]::new()
    if (Test-Path -LiteralPath $ClaudeConfigPath -PathType Leaf) {
        [void]$files.Add((New-McConfigSourceFileRecord -Path $ClaudeConfigPath -Format json -Role mcp-config))
        try {
            $claude = Read-McJson -Path $ClaudeConfigPath
            foreach ($entry in (Get-McPropertyEntries -InputObject (Get-McCollectionProperty -InputObject $claude -Name 'mcpServers'))) {
                Add-McMcpServer -Tool 'claude-code' -Scope 'user' -Name ([string]$entry.Name) -Definition $entry.Value
            }
        }
        catch {
            Add-McProjectionRedaction -Redactions $Redactions -Path 'mcp.claude-code' -Reason 'unparseable-source'
        }
    }
    if (Test-Path -LiteralPath $GeminiSettingsPath -PathType Leaf) {
        [void]$files.Add((New-McConfigSourceFileRecord -Path $GeminiSettingsPath -Format json -Role mcp-config))
        try {
            $gemini = Read-McJson -Path $GeminiSettingsPath
            foreach ($entry in (Get-McPropertyEntries -InputObject (Get-McCollectionProperty -InputObject $gemini -Name 'mcpServers'))) {
                Add-McMcpServer -Tool 'gemini-cli' -Scope 'user' -Name ([string]$entry.Name) -Definition $entry.Value
            }
        }
        catch {
            Add-McProjectionRedaction -Redactions $Redactions -Path 'mcp.gemini-cli' -Reason 'unparseable-source'
        }
    }
    if (Test-Path -LiteralPath $CodexConfigPath -PathType Leaf) {
        [void]$files.Add((New-McConfigSourceFileRecord -Path $CodexConfigPath -Format toml -Role mcp-config))
        try {
            $codexText = [System.IO.File]::ReadAllText($CodexConfigPath)
            foreach ($table in (Get-McTomlTableEntries -Text $codexText -TablePrefix 'mcp_servers')) {
                $definition = [pscustomobject][ordered]@{
                    command = [string](Get-McCollectionProperty -InputObject $table.properties -Name 'command')
                    args    = @(Get-McCollectionProperty -InputObject $table.properties -Name 'args')
                }
                Add-McMcpServer -Tool 'codex-cli' -Scope 'user' -Name ([string]$table.name) -Definition $definition
            }
        }
        catch {
            Add-McProjectionRedaction -Redactions $Redactions -Path 'mcp.codex-cli' -Reason 'unparseable-source'
        }
    }
    if (Test-Path -LiteralPath $CursorMcpPath -PathType Leaf) {
        [void]$files.Add((New-McConfigSourceFileRecord -Path $CursorMcpPath -Format json -Role mcp-config))
        try {
            $cursor = Read-McJson -Path $CursorMcpPath
            foreach ($entry in (Get-McPropertyEntries -InputObject (Get-McCollectionProperty -InputObject $cursor -Name 'mcpServers'))) {
                Add-McMcpServer -Tool 'cursor' -Scope 'user' -Name ([string]$entry.Name) -Definition $entry.Value
            }
        }
        catch {
            Add-McProjectionRedaction -Redactions $Redactions -Path 'mcp.cursor' -Reason 'unparseable-source'
        }
    }

    $unresolved = @(
        'omp: no file-based MCP configuration discovered; OMP state databases are never read by MachineContext'
        'dsh: no file-based MCP configuration discovered'
        'zcode: no file-based MCP configuration discovered'
        'agy: no file-based MCP configuration discovered'
    )

    return [pscustomobject][ordered]@{
        schema_version = 1
        id             = 'mcp-inventory'
        kind           = 'mcp-inventory'
        source         = [pscustomobject][ordered]@{
            files = @($files)
        }
        observed       = [pscustomobject][ordered]@{
            value_basis = 'configured-local'
            servers     = @($servers)
            unresolved  = $unresolved
            redactions  = @($Redactions)
        }
        curated        = [pscustomobject][ordered]@{}
    }
}

function Get-McConfigProfileObservations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoRoot,

        [string]$OmpAgentRoot = (Join-Path $env:USERPROFILE '.omp\agent'),
        [string]$DshConfigRoot = (Join-Path $env:USERPROFILE '.dsh'),
        [string]$ZcodeAppDataRoot = 'D:\ZCode\appdata\.zcode\v2',
        [string]$ZcodeUserProfileRoot = (Join-Path $env:USERPROFILE '.zcode\v2'),
        [string]$OpencodexConfigRoot = (Join-Path $env:USERPROFILE '.opencodex'),
        [string]$ClaudeConfigPath = (Join-Path $env:USERPROFILE '.claude.json'),
        [string]$GeminiSettingsPath = (Join-Path $env:USERPROFILE '.gemini\settings.json'),
        [string]$CodexConfigPath = (Join-Path $env:USERPROFILE '.codex\config.toml'),
        [string]$CursorMcpPath = (Join-Path $env:USERPROFILE '.cursor\mcp.json')
    )

    $profiles = [System.Collections.Generic.List[object]]::new()
    $profileStates = [System.Collections.Generic.List[object]]::new()
    $warnings = [System.Collections.Generic.List[string]]::new()

    $ompPresent = (-not [string]::IsNullOrWhiteSpace($OmpAgentRoot)) -and (
        (Test-Path -LiteralPath (Join-Path $OmpAgentRoot 'config.yml') -PathType Leaf) -or
        (Test-Path -LiteralPath (Join-Path $OmpAgentRoot 'models.yml') -PathType Leaf))
    $dshPresent = (-not [string]::IsNullOrWhiteSpace($DshConfigRoot)) -and (Test-Path -LiteralPath (Join-Path $DshConfigRoot 'settings.yaml') -PathType Leaf)
    $zcodePresent = (-not [string]::IsNullOrWhiteSpace($ZcodeAppDataRoot)) -and (Test-Path -LiteralPath (Join-Path $ZcodeAppDataRoot 'config.json') -PathType Leaf)
    $opencodexPresent = (-not [string]::IsNullOrWhiteSpace($OpencodexConfigRoot)) -and (Test-Path -LiteralPath (Join-Path $OpencodexConfigRoot 'config.json') -PathType Leaf)
    $codexPresent = (-not [string]::IsNullOrWhiteSpace($CodexConfigPath)) -and (Test-Path -LiteralPath $CodexConfigPath -PathType Leaf)

    foreach ($projector in @(
            [pscustomobject]@{ name = 'omp'; present = $ompPresent; action = { Get-McOmpConfigProfile -AgentRoot $OmpAgentRoot } },
            [pscustomobject]@{ name = 'dsh'; present = $dshPresent; action = { Get-McDshConfigProfile -ConfigRoot $DshConfigRoot } },
            [pscustomobject]@{ name = 'zcode'; present = $zcodePresent; action = { Get-McZcodeConfigProfile -AppDataRoot $ZcodeAppDataRoot -UserProfileRoot $ZcodeUserProfileRoot } },
            [pscustomobject]@{ name = 'opencodex'; present = $opencodexPresent; action = { Get-McOpencodexConfigProfile -ConfigRoot $OpencodexConfigRoot } },
            [pscustomobject]@{ name = 'codex-cli'; present = $codexPresent; action = { Get-McCodexConfigProfile -ConfigPath $CodexConfigPath } }
        )) {
        if (-not $projector.present) {
            # Confirmed absence is an observation, not a failure: reconciliation
            # marks the last-known profile stale instead of leaving it current.
            [void]$profileStates.Add([pscustomobject][ordered]@{ tool = $projector.name; state = 'source-missing' })
            continue
        }
        try {
            $profile = & $projector.action
            if ($null -ne $profile) {
                [void]$profiles.Add($profile)
            }
            else {
                [void]$profileStates.Add([pscustomobject][ordered]@{ tool = $projector.name; state = 'failed' })
                [void]$warnings.Add(('{0}: projection returned no record' -f $projector.name))
            }
        }
        catch {
            # A parser/provider failure keeps the previous profile untouched.
            [void]$profileStates.Add([pscustomobject][ordered]@{ tool = $projector.name; state = 'failed' })
            [void]$warnings.Add(('{0}: projection failed: {1}' -f $projector.name, (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message)))
        }
    }

    $mcp = Get-McMcpInventoryRecord -ClaudeConfigPath $ClaudeConfigPath -GeminiSettingsPath $GeminiSettingsPath -CodexConfigPath $CodexConfigPath -CursorMcpPath $CursorMcpPath

    $health = if ($warnings.Count -gt 0) { 'partial' } else { 'success' }
    return New-McProviderPayload -Value ([pscustomobject][ordered]@{
            profiles       = @($profiles)
            profile_states = @($profileStates)
            mcp            = $mcp
        }) -Health $health -ResultCount ($profiles.Count + 1) -Warnings $warnings -CoverageComplete $true
}
