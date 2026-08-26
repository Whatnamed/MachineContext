Set-StrictMode -Version Latest

# This file is dot-sourced by every entry point. Keep the load order explicit so
# a script can be run directly with only the PowerShell 7 runtime.
. (Join-Path $PSScriptRoot 'json.ps1')
. (Join-Path $PSScriptRoot 'normalize.ps1')
. (Join-Path $PSScriptRoot 'probe.ps1')
. (Join-Path $PSScriptRoot 'diagnostics.ps1')
. (Join-Path $PSScriptRoot 'staging.ps1')
. (Join-Path $PSScriptRoot 'privacy.ps1')
