
param(
    [ValidateSet('Debug','Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$Dotnet = & "$PSScriptRoot\resolve-dotnet11.ps1" | Select-Object -Last 1
if ([string]::IsNullOrWhiteSpace($Dotnet) -or -not (Test-Path $Dotnet)) {
    throw "Could not resolve a usable .NET SDK executable."
}

$Solution = Join-Path $PSScriptRoot '..\Retro96.Plugin.SDK.sln'
# Start clean so a previously built plugin DLL can never be mistaken for the
# current SDK contract. This is especially important after the 1.0.1 contract
# assembly identity correction (Retro96.Plugin.SDK -> Retro96).
Remove-Item -Path @((Join-Path $PSScriptRoot 'artifacts'), (Join-Path $PSScriptRoot '..\examples\Retro96.SamplePlugin\dist')) -Recurse -Force -ErrorAction SilentlyContinue

& $Dotnet restore $Solution
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Dotnet build $Solution -c $Configuration --no-restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Packaging is explicit, not an accidental side effect of every ordinary build.
& $Dotnet pack (Join-Path $PSScriptRoot 'Retro96.Plugin.SDK.csproj') -c $Configuration --no-build --no-restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Dll = Join-Path $PSScriptRoot "artifacts\bin\$Configuration\Retro96.dll"
if (-not (Test-Path $Dll)) { throw "SDK DLL was not produced: $Dll" }

$NupkgDir = Join-Path $PSScriptRoot 'artifacts\packages'
Write-Host "SDK contract DLL: $Dll"
Write-Host "SDK packages: $NupkgDir"
