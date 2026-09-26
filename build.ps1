param(
    [ValidateSet('Debug','Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
& "$PSScriptRoot/bootstrap-dotnet11.ps1"
$Dotnet = Join-Path $PSScriptRoot '.dotnet\dotnet.exe'
& $Dotnet restore "$PSScriptRoot/Retro96.Plugin.SDK.csproj"
& $Dotnet build "$PSScriptRoot/Retro96.Plugin.SDK.csproj" -c $Configuration --no-restore
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$Dll = Join-Path $PSScriptRoot "artifacts\bin\$Configuration\Retro96.Plugin.SDK.dll"
$NupkgDir = Join-Path $PSScriptRoot 'artifacts\packages'
Write-Host "SDK DLL: $Dll"
Write-Host "SDK packages: $NupkgDir"
