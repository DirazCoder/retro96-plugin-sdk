
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
& $Dotnet restore $Solution
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Dotnet build $Solution -c $Configuration --no-restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Packaging is explicit, not an accidental side effect of every ordinary build.
& $Dotnet pack (Join-Path $PSScriptRoot 'Retro96.Plugin.SDK.csproj') -c $Configuration --no-build --no-restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Dll = Join-Path $PSScriptRoot "artifacts\bin\$Configuration\Retro96.Plugin.SDK.dll"
if (-not (Test-Path $Dll)) { throw "SDK DLL was not produced: $Dll" }

$NupkgDir = Join-Path $PSScriptRoot 'artifacts\packages'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Retro96\PluginSDK'
$FeedDir = Join-Path $InstallDir 'packages'
New-Item -ItemType Directory -Force -Path $InstallDir, $FeedDir | Out-Null
Copy-Item -Force $Dll (Join-Path $InstallDir 'Retro96.Plugin.SDK.dll')
Get-ChildItem -Path $NupkgDir -Filter 'Retro96.Plugin.SDK.*.nupkg' -File | Copy-Item -Destination $FeedDir -Force

Write-Host "SDK DLL: $Dll"
Write-Host "SDK packages: $NupkgDir"
Write-Host "Installed SDK contract: $InstallDir\Retro96.Plugin.SDK.dll"
Write-Host "Local NuGet feed for Retro96 host: $FeedDir"
