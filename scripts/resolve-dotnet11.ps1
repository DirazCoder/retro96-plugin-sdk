
param()

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Get-UsableDotnet {
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return $null }

    $previous = Get-Location
    try {
        # global.json is intentionally authoritative. Execute dotnet from this SDK
        # directory so the installed SDK is accepted only when the pinned SDK can
        # actually resolve here. If it cannot, the caller falls back to bootstrap.
        Set-Location $PSScriptRoot
        $version = (& $cmd.Source --version 2>$null).Trim()
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($version)) {
            return $cmd.Source
        }
    }
    catch { }
    finally {
        Set-Location $previous
    }

    return $null
}

$dotnet = Get-UsableDotnet
if ($null -eq $dotnet) {
    & "$PSScriptRoot\bootstrap-dotnet11.ps1"
    if ($LASTEXITCODE -ne 0) { throw "Failed to bootstrap the pinned .NET 11 SDK." }
    $dotnet = Join-Path $PSScriptRoot '.dotnet\dotnet.exe'
}

if (-not (Test-Path $dotnet)) {
    throw "A usable .NET SDK could not be located."
}

& $dotnet --version
$dotnet
