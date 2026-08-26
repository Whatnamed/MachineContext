Set-StrictMode -Version Latest

function Get-McNvidiaSmiObservation {
    [CmdletBinding()]
    param()

    $knownPaths = @(
        '%ProgramFiles%\NVIDIA Corporation\NVSMI\nvidia-smi.exe',
        '%SystemRoot%\System32\nvidia-smi.exe'
    )
    $candidates = @(Get-McHostToolCandidates -Command 'nvidia-smi.exe' -KnownPaths $knownPaths)
    if ($candidates.Count -eq 0) {
        return New-McProviderPayload -Value ([pscustomobject][ordered]@{
                gpu_verifications = @()
                check = [pscustomobject][ordered]@{ status = 'unavailable'; executable = $null }
            }) -Health 'unavailable' -Optional $true -CoverageComplete $false
    }

    $primary = $candidates[0]
    $probe = Invoke-McProbe -Executable ([string]$primary.path) -Arguments @('--query-gpu=name,driver_version,memory.total', '--format=csv,noheader,nounits') -Provider 'nvidia-smi' -ProbeName 'gpu-memory-driver' -TimeoutMs 10000 -OutputCapBytes 32768 -ResolutionScope 'windows-host'
    if ($probe.status -ne 'success') {
        $warning = "nvidia-smi verifier status: $($probe.status)"
        return New-McProviderPayload -Value ([pscustomobject][ordered]@{
                gpu_verifications = @()
                candidates = @([pscustomobject][ordered]@{
                        candidate_id = New-McStableId -Kind 'command-candidate' -Identity ("nvidia-smi|{0}" -f $primary.path)
                        kind_hint = 'gpu-verifier'
                        name_hint = 'NVIDIA GPU verifier'
                        path = ConvertTo-McNormalizedPath -Path ([string]$primary.path)
                        source = 'nvidia-smi'
                        source_key = 'nvidia-smi.exe'
                        confidence_hint = 'low'
                        evidence = @([pscustomobject][ordered]@{ type = 'command_resolves'; verifier_status = [string]$probe.status })
                    })
                check = [pscustomobject][ordered]@{ status = [string]$probe.status; executable = ConvertTo-McNormalizedPath -Path ([string]$primary.path) }
            }) -Health $failureHealth -Warnings @($warning) -Optional $true -CoverageComplete $false
    }

    $records = @(ConvertFrom-McNvidiaSmiText -Text ([string]$probe.stdout))
    if ($records.Count -eq 0) {
        return New-McProviderPayload -Value ([pscustomobject][ordered]@{
                gpu_verifications = @()
                check = [pscustomobject][ordered]@{ status = 'success'; executable = ConvertTo-McNormalizedPath -Path ([string]$primary.path); gpu_count = 0 }
            }) -Health 'partial' -Warnings @('nvidia-smi returned no parseable GPU records') -Optional $true -CoverageComplete $true
    }

    foreach ($record in $records) {
        [void](Add-Member -InputObject $record -MemberType NoteProperty -Name evidence -Value @([pscustomobject][ordered]@{
                provider = 'nvidia-smi'
                provider_key = 'gpu-memory-driver'
                fields = @('name', 'driver_version', 'vram_bytes')
                confidence = 'high'
            }) -Force)
    }
    return New-McProviderPayload -Value ([pscustomobject][ordered]@{
            gpu_verifications = @($records)
            check = [pscustomobject][ordered]@{ status = 'success'; executable = ConvertTo-McNormalizedPath -Path ([string]$primary.path); gpu_count = $records.Count }
        }) -Health 'success' -ResultCount $records.Count -Optional $true -CoverageComplete $true
}
