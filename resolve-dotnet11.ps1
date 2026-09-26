
param()

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Get-UsableDotnet {
    $cmd = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { return $null }

    try {
        $version = (& $cmd.Source --version 2>$null).Trim()
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($version)) {
            # Run from the SDK directory so global.json is applied by dotnet itself.
            return $cmd.Source
        }
    }
    catch { }

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
