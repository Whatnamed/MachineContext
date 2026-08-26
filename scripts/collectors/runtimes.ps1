Set-StrictMode -Version Latest

function Get-McRuntimeDefinitions {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ id = 'node'; name = 'Node.js'; kind = 'runtime'; command = 'node'; args = @('--version') },
        [pscustomobject]@{ id = 'python'; name = 'Python'; kind = 'runtime'; command = 'python'; args = @('--version') },
        [pscustomobject]@{ id = 'python-launcher'; name = 'Python Launcher'; kind = 'runtime'; command = 'py'; args = @('--version') },
        [pscustomobject]@{ id = 'go'; name = 'Go'; kind = 'runtime'; command = 'go'; args = @('version') },
        [pscustomobject]@{ id = 'rustc'; name = 'Rust compiler'; kind = 'compiler'; command = 'rustc'; args = @('--version') },
        [pscustomobject]@{ id = 'cargo'; name = 'Cargo'; kind = 'package-manager'; command = 'cargo'; args = @('--version') },
        [pscustomobject]@{ id = 'rustup'; name = 'rustup'; kind = 'version-manager'; command = 'rustup'; args = @('--version') },
        [pscustomobject]@{ id = 'java'; name = 'Java'; kind = 'runtime'; command = 'java'; args = @('-version') },
        [pscustomobject]@{ id = 'dotnet'; name = '.NET SDK/runtime'; kind = 'runtime'; command = 'dotnet'; args = @('--version') },
        [pscustomobject]@{ id = 'flutter'; name = 'Flutter'; kind = 'sdk'; command = 'flutter'; args = @('--version') },
        [pscustomobject]@{ id = 'dart'; name = 'Dart'; kind = 'runtime'; command = 'dart'; args = @('--version') },
        [pscustomobject]@{ id = 'ruby'; name = 'Ruby'; kind = 'runtime'; command = 'ruby'; args = @('--version') },
        [pscustomobject]@{ id = 'php'; name = 'PHP'; kind = 'runtime'; command = 'php'; args = @('--version') },
        [pscustomobject]@{ id = 'deno'; name = 'Deno'; kind = 'runtime'; command = 'deno'; args = @('--version') },
        [pscustomobject]@{ id = 'npm'; name = 'npm'; kind = 'package-manager'; command = 'npm'; args = @('--version') },
        [pscustomobject]@{ id = 'pnpm'; name = 'pnpm'; kind = 'package-manager'; command = 'pnpm'; args = @('--version') },
        [pscustomobject]@{ id = 'yarn'; name = 'Yarn'; kind = 'package-manager'; command = 'yarn'; args = @('--version') },
        [pscustomobject]@{ id = 'bun'; name = 'Bun'; kind = 'runtime'; command = 'bun'; args = @('--version') },
        [pscustomobject]@{ id = 'pip'; name = 'pip'; kind = 'package-manager'; command = 'pip'; args = @('--version') },
        [pscustomobject]@{ id = 'pipx'; name = 'pipx'; kind = 'package-manager'; command = 'pipx'; args = @('--version') },
        [pscustomobject]@{ id = 'uv'; name = 'uv'; kind = 'package-manager'; command = 'uv'; args = @('--version') },
        [pscustomobject]@{ id = 'uvx'; name = 'uvx'; kind = 'package-manager'; command = 'uvx'; args = @('--version') },
        [pscustomobject]@{ id = 'conda'; name = 'conda'; kind = 'package-manager'; command = 'conda'; args = @('--version') },
        [pscustomobject]@{ id = 'mamba'; name = 'mamba'; kind = 'package-manager'; command = 'mamba'; args = @('--version') },
        [pscustomobject]@{ id = 'nvm'; name = 'nvm-windows'; kind = 'version-manager'; command = 'nvm'; args = @('version') },
        [pscustomobject]@{ id = 'fnm'; name = 'fnm'; kind = 'version-manager'; command = 'fnm'; args = @('--version') },
        [pscustomobject]@{ id = 'volta'; name = 'Volta'; kind = 'version-manager'; command = 'volta'; args = @('--version') },
        [pscustomobject]@{ id = 'pyenv'; name = 'pyenv'; kind = 'version-manager'; command = 'pyenv'; args = @('--version') },
        [pscustomobject]@{ id = 'mise'; name = 'mise'; kind = 'version-manager'; command = 'mise'; args = @('--version') },
        [pscustomobject]@{ id = 'git'; name = 'Git'; kind = 'cli'; command = 'git'; args = @('--version') },
        [pscustomobject]@{ id = 'git-lfs'; name = 'Git LFS'; kind = 'cli'; command = 'git-lfs'; args = @('--version') },
        [pscustomobject]@{ id = 'cmake'; name = 'CMake'; kind = 'build-tool'; command = 'cmake'; args = @('--version') },
        [pscustomobject]@{ id = 'ninja'; name = 'Ninja'; kind = 'build-tool'; command = 'ninja'; args = @('--version') },
        [pscustomobject]@{ id = 'vswhere'; name = 'Visual Studio locator'; kind = 'tool'; command = 'vswhere'; args = @('-version') },
        [pscustomobject]@{ id = 'adb'; name = 'Android Debug Bridge'; kind = 'sdk-tool'; command = 'adb'; args = @('version') },
        [pscustomobject]@{ id = 'nvcc'; name = 'CUDA compiler'; kind = 'compiler'; command = 'nvcc'; args = @('--version') },
        [pscustomobject]@{ id = 'code'; name = 'Visual Studio Code'; kind = 'developer-application'; command = 'code'; args = @('--version') },
        [pscustomobject]@{ id = 'gh'; name = 'GitHub CLI'; kind = 'cloud-cli'; command = 'gh'; args = @('--version') },
        [pscustomobject]@{ id = 'docker'; name = 'Docker CLI'; kind = 'developer-application'; command = 'docker'; args = @('--version') },
        [pscustomobject]@{ id = 'kubectl'; name = 'kubectl'; kind = 'cloud-cli'; command = 'kubectl'; args = @('version', '--client=true', '--output=json') },
        [pscustomobject]@{ id = 'supabase'; name = 'Supabase CLI'; kind = 'cloud-cli'; command = 'supabase'; args = @('--version') },
        [pscustomobject]@{ id = 'vercel'; name = 'Vercel CLI'; kind = 'cloud-cli'; command = 'vercel'; args = @('--version') },
        [pscustomobject]@{ id = 'wrangler'; name = 'Wrangler'; kind = 'cloud-cli'; command = 'wrangler'; args = @('--version') },
        [pscustomobject]@{ id = 'firebase'; name = 'Firebase CLI'; kind = 'cloud-cli'; command = 'firebase'; args = @('--version') },
        [pscustomobject]@{ id = 'aws'; name = 'AWS CLI'; kind = 'cloud-cli'; command = 'aws'; args = @('--version') },
        [pscustomobject]@{ id = 'az'; name = 'Azure CLI'; kind = 'cloud-cli'; command = 'az'; args = @('--version') },
        [pscustomobject]@{ id = 'gcloud'; name = 'Google Cloud CLI'; kind = 'cloud-cli'; command = 'gcloud'; args = @('--version') },
        [pscustomobject]@{ id = 'terraform'; name = 'Terraform'; kind = 'infra-cli'; command = 'terraform'; args = @('-version') },
        [pscustomobject]@{ id = 'winget'; name = 'winget'; kind = 'package-manager'; command = 'winget'; args = @('--version') },
        [pscustomobject]@{ id = 'choco'; name = 'Chocolatey'; kind = 'package-manager'; command = 'choco'; args = @('--version') },
        [pscustomobject]@{ id = 'scoop'; name = 'Scoop'; kind = 'package-manager'; command = 'scoop'; args = @('--version') }
    )
}

function Get-McPackageManagerDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Definition,

        [Parameter(Mandatory)]
        [object]$Primary
    )

    $details = [ordered]@{}
    if ($Definition.id -eq 'npm') {
        foreach ($setting in @(
                [pscustomobject]@{ id = 'prefix'; args = @('config', 'get', 'prefix') },
                [pscustomobject]@{ id = 'cache'; args = @('config', 'get', 'cache') }
            )) {
            $probe = Invoke-McProbe -Executable $Primary.path -Arguments @($setting.args) -Provider 'runtimes-package-managers-toolchain' -ProbeName ("npm-{0}" -f $setting.id) -TimeoutMs 5000 -OutputCapBytes 8192
            if ($probe.status -eq 'success') {
                $text = Get-McProbeVersionText -Probe $probe
                if (-not [string]::IsNullOrWhiteSpace($text) -and $text -notmatch '^(undefined|null)$') {
                    $details[$setting.id] = ConvertTo-McNormalizedPath -Path $text.Trim()
                }
            }
        }
    }
    elseif ($Definition.id -eq 'pip') {
        $probe = Invoke-McProbe -Executable $Primary.path -Arguments @('cache', 'dir') -Provider 'runtimes-package-managers-toolchain' -ProbeName 'pip-cache' -TimeoutMs 5000 -OutputCapBytes 8192
        if ($probe.status -eq 'success') {
            $text = Get-McProbeVersionText -Probe $probe
            if (-not [string]::IsNullOrWhiteSpace($text)) { $details.cache = ConvertTo-McNormalizedPath -Path $text.Trim() }
        }
    }

    return [pscustomobject]$details
}

function Get-McRuntimeToolObservations {
    [CmdletBinding()]
    param()

    $entities = [System.Collections.Generic.List[object]]::new()
    $candidates = [System.Collections.Generic.List[object]]::new()
    $relationships = [System.Collections.Generic.List[object]]::new()
    $failureCount = 0

    foreach ($definition in (Get-McRuntimeDefinitions)) {
        $candidatesForCommand = @(Get-McExecutableCandidates -Executable $definition.command)
        if ($candidatesForCommand.Count -eq 0) {
            continue
        }

        $primary = $candidatesForCommand[0]
        $probe = Invoke-McProbe -Executable $primary.path -Arguments @($definition.args) -Provider 'runtimes-package-managers-toolchain' -ProbeName ([string]$definition.id) -TimeoutMs 8000 -OutputCapBytes 16384
        if ($probe.status -ne 'success') {
            $failureCount++
            [void]$candidates.Add([pscustomobject][ordered]@{
                candidate_id = New-McStableId -Kind 'command-candidate' -Identity ("{0}|{1}" -f $definition.id, $primary.path)
                kind_hint = [string]$definition.kind
                name_hint = [string]$definition.name
                path = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
                source = 'command'
                source_key = [string]$definition.command
                confidence_hint = 'low'
                evidence = @([pscustomobject][ordered]@{
                    type = 'command_resolves'
                    verifier_status = [string]$probe.status
                })
            })
            continue
        }

        $executable = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
        $installRoot = ConvertTo-McNormalizedPath -Path (Split-Path -Parent ([string]$primary.path))
        $observed = [ordered]@{
            present = $true
            version = (Get-McProbeVersionText -Probe $probe)
            executable = $executable
            command_resolution = @(
                foreach ($candidate in $candidatesForCommand) {
                    [pscustomobject][ordered]@{
                        executable = ConvertTo-McNormalizedPath -Path ([string]$candidate.path)
                        command_type = [string]$candidate.command_type
                    }
                }
            )
            install = [ordered]@{
                root = $installRoot
            }
            evidence = @([pscustomobject][ordered]@{
                provider = 'command'
                provider_key = [string]$definition.command
                fields = @('present', 'version', 'executable', 'command_resolution')
                confidence = 'high'
            })
        }

        $details = Get-McPackageManagerDetails -Definition $definition -Primary $primary
        foreach ($property in (Get-McPropertyEntries -InputObject $details)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
                if ($null -eq $observed.install) { $observed.install = [ordered]@{} }
                $observed.install[$property.Name] = $property.Value
            }
        }

        [void]$entities.Add([pscustomobject][ordered]@{
            id = [string]$definition.id
            kind = [string]$definition.kind
            name = [string]$definition.name
            observed = [pscustomobject]$observed
        })
    }

    $node = @($entities | Where-Object id -eq 'node' | Select-Object -First 1)
    foreach ($managerId in @('nvm', 'fnm', 'volta', 'mise')) {
        $manager = @($entities | Where-Object id -eq $managerId | Select-Object -First 1)
        if ($node.Count -gt 0 -and $manager.Count -gt 0) {
            $nodePath = [string]$node[0].observed.executable
            $managerPath = [string]$manager[0].observed.executable
            if ($nodePath -and $managerPath -and $nodePath.StartsWith((Split-Path -Parent $managerPath), [System.StringComparison]::OrdinalIgnoreCase)) {
                [void]$relationships.Add([pscustomobject][ordered]@{
                    from = 'node'
                    relation = 'managed_by'
                    to = $managerId
                    origin = 'inferred'
                    evidence = @([pscustomobject][ordered]@{ provider = 'command'; fields = @('executable') })
                })
            }
        }
    }

    $health = if ($failureCount -gt 0) { 'partial' } else { 'success' }
    return New-McProviderPayload -Value ([pscustomobject][ordered]@{
            entities = @($entities)
            candidates = @($candidates)
            relationships = @($relationships)
        }) -Health $health -ResultCount $entities.Count -CoverageComplete $false
}
