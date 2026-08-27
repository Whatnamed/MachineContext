Set-StrictMode -Version Latest

# Source-specific, allowlisted AI configuration projections. Each projector
# reads the real config files on this machine and emits a safe, source-native
# projection. Raw config content, credential values, and credential-named
# fields never reach the projection; credential fields survive only as
# environment-variable names (credentialEnvName / credential_env_names).

function Repair-McProjectionUrls {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Redactions,

        [string]$Path = '$'
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return $Value }
    if (Test-McMapping -InputObject $Value) {
        $mapping = [ordered]@{}
        foreach ($entry in (Get-McPropertyEntries -InputObject $Value)) {
            $entryPath = "{0}.{1}" -f $Path, $entry.Name
            if ($entry.Value -is [string] -and [string]$entry.Name -match '(?i)^base_?url$') {
                $mapping[[string]$entry.Name] = ConvertTo-McProjectionSafeUrl -Url ([string]$entry.Value) -Redactions $Redactions -Path $entryPath
            }
            else {
                $mapping[[string]$entry.Name] = Repair-McProjectionUrls -Value $entry.Value -Redactions $Redactions -Path $entryPath
            }
        }
        return $mapping
    }
    if (Test-McSequence -InputObject $Value) {
        $items = [System.Collections.Generic.List[object]]::new()
        $index = 0
        foreach ($item in $Value) {
            [void]$items.Add((Repair-McProjectionUrls -Value $item -Redactions $Redactions -Path ("{0}[{1}]" -f $Path, $index)))
            $index++
        }
        Write-Output -NoEnumerate -InputObject ([object[]]$items.ToArray())
        return
    }
    return $Value
}

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

    if ($hasConfig) {
        $config = Read-McConfigYaml -Path $configYml
        $configProjection = [ordered]@{}
        foreach ($key in @('shellPath', 'providers', 'modelRoles', 'defaultThinkingLevel')) {
            $value = Get-McCollectionProperty -InputObject $config -Name $key
            if ($null -ne $value) {
                $configProjection[$key] = ConvertTo-McSafeProjectionValue -Value $value -Path ("omp.config.{0}" -f $key) -Redactions $Redactions
            }
        }
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
        $providersProjection = [ordered]@{}
        foreach ($providerEntry in (Get-McPropertyEntries -InputObject $providers)) {
            $providerProjection = ConvertTo-McSafeProjectionValue -Value $providerEntry.Value -Path ("omp.models.providers.{0}" -f $providerEntry.Name) -Redactions $Redactions -EnvReferenceKeys @('apikey', 'apikeyenv')
            $providerProjection = Repair-McProjectionUrls -Value $providerProjection -Redactions $Redactions -Path ("omp.models.providers.{0}" -f $providerEntry.Name)
            if ($null -ne $providerProjection) { $providersProjection[[string]$providerEntry.Name] = $providerProjection }
            $reference = Get-McCollectionProperty -InputObject $providerEntry.Value -Name 'apiKey'
            if ((Test-McEnvVarNameShape -Value ([string]$reference)) -and (-not $envNames.Contains([string]$reference))) {
                [void]$envNames.Add([string]$reference)
            }
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

    return (New-McConfigProfileRecord -Id 'omp-config' -Tool 'omp' -ConfigRoot (ConvertTo-McNormalizedPath -Path $AgentRoot) `
        -Files $files -Projection $projection -Redactions $Redactions -CredentialEnvNames @($envNames) `
        -WireVerification 'not-wire-verified' -Evidence $evidence)
}

function ConvertTo-McProviderUrlPreSanitized {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Provider,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Redactions,

        [Parameter(Mandatory)]
        [string]$Path
    )

    # Sanitize credential-bearing base URLs before the safe walker, so a URL
    # with userinfo/query is reduced to its safe form instead of being dropped.
    if (-not (Test-McMapping -InputObject $Provider)) { return $Provider }
    $copy = [ordered]@{}
    foreach ($entry in (Get-McPropertyEntries -InputObject $Provider)) {
        $key = [string]$entry.Name
        if ($entry.Value -is [string] -and $key -match '(?i)^base_?url$') {
            $copy[$key] = ConvertTo-McProjectionSafeUrl -Url ([string]$entry.Value) -Redactions $Redactions -Path ("{0}.{1}" -f $Path, $key)
        }
        else {
            $copy[$key] = $entry.Value
        }
    }
    return $copy
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

    foreach ($section in (Get-McPropertyEntries -InputObject $settings)) {
        $sectionName = [string]$section.Name
        if ($sectionName -eq 'agent-default-model' -or $sectionName -eq 'agent-presets') {
            $projection[$sectionName] = ConvertTo-McSafeProjectionValue -Value $section.Value -Path ("dsh.{0}" -f $sectionName) -Redactions $Redactions
            [void]$projectedSections.Add($sectionName)
            continue
        }
        if (-not $sectionName.StartsWith('llm-')) { continue }
        $sectionProjection = $null
        $providers = Get-McCollectionProperty -InputObject $section.Value -Name 'providers'
        if ($null -ne $providers) {
            $providersProjection = [ordered]@{}
            foreach ($providerEntry in (Get-McPropertyEntries -InputObject $providers)) {
                $preSanitized = ConvertTo-McProviderUrlPreSanitized -Provider $providerEntry.Value -Redactions $Redactions -Path ("dsh.{0}.providers.{1}" -f $sectionName, $providerEntry.Name)
                $providerProjection = ConvertTo-McSafeProjectionValue -Value $preSanitized -Path ("dsh.{0}.providers.{1}" -f $sectionName, $providerEntry.Name) -Redactions $Redactions -EnvReferenceKeys @('apikeyenv', 'apikey')
                $providerProjection = Repair-McProjectionUrls -Value $providerProjection -Redactions $Redactions -Path ("dsh.{0}.providers.{1}" -f $sectionName, $providerEntry.Name)
                if ($null -ne $providerProjection) { $providersProjection[[string]$providerEntry.Name] = $providerProjection }
                $reference = Get-McCollectionProperty -InputObject $providerEntry.Value -Name 'apiKeyEnv'
                if ((Test-McEnvVarNameShape -Value ([string]$reference)) -and (-not $envNames.Contains([string]$reference))) {
                    [void]$envNames.Add([string]$reference)
                }
            }
            $sectionProjection = [ordered]@{ providers = $providersProjection }
        }
        elseif ($null -ne (Get-McCollectionProperty -InputObject $section.Value -Name 'baseURL') -or $null -ne (Get-McCollectionProperty -InputObject $section.Value -Name 'models')) {
            $preSanitizedSection = ConvertTo-McProviderUrlPreSanitized -Provider $section.Value -Redactions $Redactions -Path ("dsh.{0}" -f $sectionName)
            $sectionProjection = ConvertTo-McSafeProjectionValue -Value $preSanitizedSection -Path ("dsh.{0}" -f $sectionName) -Redactions $Redactions -EnvReferenceKeys @('apikeyenv', 'apikey')
            $sectionProjection = Repair-McProjectionUrls -Value $sectionProjection -Redactions $Redactions -Path ("dsh.{0}" -f $sectionName)
        }
        if ($null -ne $sectionProjection) {
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

    $primaryConfig = $null
    $secondaryConfig = $null
    $hasPrimary = $false
    $hasSecondary = $false
    if (-not [string]::IsNullOrWhiteSpace($AppDataRoot)) {
        $primaryConfig = Join-Path $AppDataRoot 'config.json'
        $hasPrimary = Test-Path -LiteralPath $primaryConfig -PathType Leaf
    }
    if (-not [string]::IsNullOrWhiteSpace($UserProfileRoot)) {
        $secondaryConfig = Join-Path $UserProfileRoot 'config.json'
        $hasSecondary = Test-Path -LiteralPath $secondaryConfig -PathType Leaf
    }
    if (-not $hasPrimary -and -not $hasSecondary) { return $null }

    $redactions = [System.Collections.Generic.List[object]]::new()
    $files = [System.Collections.Generic.List[object]]::new()
    if ($hasPrimary) { [void]$files.Add((New-McConfigSourceFileRecord -Path $primaryConfig -Format json -Role config)) }
    if ($hasSecondary) { [void]$files.Add((New-McConfigSourceFileRecord -Path $secondaryConfig -Format json -Role sensitive-config-copy)) }
    if ($hasSecondary) { [void]$files.Add((New-McConfigSourceFileRecord -Path (Join-Path $UserProfileRoot 'setting.json') -Format json -Role settings)) }
    if ($hasPrimary) {
        [void]$files.Add((New-McConfigSourceFileRecord -Path (Join-Path $AppDataRoot 'bot-config.json') -Format json -Role bot-config))
        [void]$files.Add((New-McConfigSourceFileRecord -Path (Join-Path $AppDataRoot 'credentials.json') -Format json -Role credential-store))
    }
    $files = @($files)

    $projection = [ordered]@{}
    $evidence = [System.Collections.Generic.List[object]]::new()
    $configPath = if ($hasPrimary) { $primaryConfig } else { $secondaryConfig }
    $config = Read-McJson -Path $configPath
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
            source_path = (ConvertTo-McNormalizedPath -Path $configPath)
            fields      = @('providers')
        })
    }

    $settingPath = $null
    if ($hasSecondary) { $settingPath = Join-Path $UserProfileRoot 'setting.json' }
    if (-not [string]::IsNullOrWhiteSpace($settingPath) -and (Test-Path -LiteralPath $settingPath -PathType Leaf)) {
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

    foreach ($name in @('port', 'defaultProvider', 'contextCapValue', 'providerContextCaps', 'clientIntegrations', 'websockets', 'codexAutoStart', 'subagentModels', 'disabledModels')) {
        $value = Get-McCollectionProperty -InputObject $config -Name $name
        if ($null -ne $value) {
            $projected = ConvertTo-McSafeProjectionValue -Value $value -Path ("opencodex.{0}" -f $name) -Redactions $Redactions
            if ($null -ne $projected) { $projection[$name] = $projected }
        }
    }

    $claudeCode = Get-McCollectionProperty -InputObject $config -Name 'claudeCode'
    if ($null -ne $claudeCode) {
        $claudeProjection = [ordered]@{}
        foreach ($name in @('enabled', 'authMode')) {
            $value = Get-McCollectionProperty -InputObject $claudeCode -Name $name
            if ($null -ne $value) { $claudeProjection[$name] = $value }
        }
        $desktopProfile = Get-McCollectionProperty -InputObject $claudeCode -Name 'desktopProfile'
        $defaults = Get-McCollectionProperty -InputObject $desktopProfile -Name 'defaults'
        if ($null -ne $defaults) {
            $claudeProjection['desktop_defaults'] = (ConvertTo-McSafeProjectionValue -Value $defaults -Path 'opencodex.claudeCode.desktopProfile.defaults' -Redactions $Redactions)
        }
        if (@(Get-McPropertyEntries -InputObject $claudeProjection).Count -gt 0) { $projection['claudeCode'] = $claudeProjection }
    }

    foreach ($sidecarName in @('webSearchSidecar', 'visionSidecar')) {
        $sidecar = Get-McCollectionProperty -InputObject $config -Name $sidecarName
        if ($null -eq $sidecar) { continue }
        $sidecarProjection = [ordered]@{}
        foreach ($entry in (Get-McPropertyEntries -InputObject $sidecar)) {
            $projected = ConvertTo-McSafeProjectionValue -Value $entry.Value -Path ("opencodex.{0}.{1}" -f $sidecarName, $entry.Name) -Redactions $Redactions
            if ($null -ne $projected) { $sidecarProjection[[string]$entry.Name] = $projected }
        }
        if (@(Get-McPropertyEntries -InputObject $sidecarProjection).Count -gt 0) { $projection[$sidecarName] = $sidecarProjection }
    }

    $providers = Get-McCollectionProperty -InputObject $config -Name 'providers'
    $providersProjection = [ordered]@{}
    foreach ($providerEntry in (Get-McPropertyEntries -InputObject $providers)) {
        $provider = $providerEntry.Value
        $providerProjection = [ordered]@{}
        $hasCredential = $false
        foreach ($entry in (Get-McPropertyEntries -InputObject $provider)) {
            $key = [string]$entry.Name
            $entryKey = ($key -replace '[-_ ]', '').ToLowerInvariant()
            $entryPath = "opencodex.providers.{0}.{1}" -f $providerEntry.Name, $key
            if ($entryKey -in @('apikey', 'apikeypool', 'apikeys')) {
                $hasCredential = $true
                Add-McProjectionRedaction -Redactions $Redactions -Path $entryPath -Reason 'credential-value'
                continue
            }
            if ($entryKey -eq 'baseurl') {
                $baseUrl = ConvertTo-McProjectionSafeUrl -Url ([string]$entry.Value) -Redactions $Redactions -Path $entryPath
                if (-not [string]::IsNullOrWhiteSpace($baseUrl)) { $providerProjection[$key] = $baseUrl }
                continue
            }
            $projected = ConvertTo-McSafeProjectionValue -Value $entry.Value -Path $entryPath -Redactions $Redactions
            if ($null -ne $projected) { $providerProjection[$key] = $projected }
        }
        if ($hasCredential) { $providerProjection['credential_configured'] = $true }
        $providersProjection[[string]$providerEntry.Name] = $providerProjection
    }
    if (@(Get-McPropertyEntries -InputObject $providersProjection).Count -gt 0) {
        $projection['providers'] = $providersProjection
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
            $safeArgs = [System.Collections.Generic.List[object]]::new()
            foreach ($argument in $args) {
                if (Test-McSafeMcpArgument -Argument ([string]$argument)) {
                    [void]$safeArgs.Add([string]$argument)
                }
                else {
                    Add-McProjectionRedaction -Redactions $Redactions -Path ("mcp.{0}.{1}.args" -f $Tool, $Name) -Reason 'unsafe-argument'
                }
            }
            if ($safeArgs.Count -gt 0) { $server['args'] = @($safeArgs) }
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
        'pi: tool not located on this machine; MCP configuration unknown'
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
    $warnings = [System.Collections.Generic.List[string]]::new()

    foreach ($projector in @(
            [pscustomobject]@{ name = 'omp'; action = { Get-McOmpConfigProfile -AgentRoot $OmpAgentRoot } },
            [pscustomobject]@{ name = 'dsh'; action = { Get-McDshConfigProfile -ConfigRoot $DshConfigRoot } },
            [pscustomobject]@{ name = 'zcode'; action = { Get-McZcodeConfigProfile -AppDataRoot $ZcodeAppDataRoot -UserProfileRoot $ZcodeUserProfileRoot } },
            [pscustomobject]@{ name = 'opencodex'; action = { Get-McOpencodexConfigProfile -ConfigRoot $OpencodexConfigRoot } }
        )) {
        try {
            $profile = & $projector.action
            if ($null -ne $profile) { [void]$profiles.Add($profile) }
        }
        catch {
            [void]$warnings.Add(('{0}: projection failed: {1}' -f $projector.name, (ConvertTo-McSafeDiagnosticText -Text $_.Exception.Message)))
        }
    }

    $mcp = Get-McMcpInventoryRecord -ClaudeConfigPath $ClaudeConfigPath -GeminiSettingsPath $GeminiSettingsPath -CodexConfigPath $CodexConfigPath -CursorMcpPath $CursorMcpPath

    $health = if ($warnings.Count -gt 0) { 'partial' } else { 'success' }
    return New-McProviderPayload -Value ([pscustomobject][ordered]@{
            profiles = @($profiles)
            mcp      = $mcp
        }) -Health $health -ResultCount ($profiles.Count + 1) -Warnings $warnings -CoverageComplete $true
}
