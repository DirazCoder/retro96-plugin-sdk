[CmdletBinding()]
param(
    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$SdkRoot = Split-Path -Parent $PSScriptRoot
Set-Location $SdkRoot

function Resolve-Dotnet {
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $resolved = & "$PSScriptRoot\resolve-dotnet11.ps1" | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($resolved) -or -not (Test-Path $resolved)) {
        throw 'Could not resolve a usable .NET 11 SDK executable.'
    }
    return $resolved
}

$dotnet = Resolve-Dotnet
$solution = Join-Path $SdkRoot 'Retro96.Plugin.SDK.sln'
$artifacts = Join-Path $SdkRoot 'artifacts'

# The solution intentionally contains only the SDK contract.
Remove-Item $artifacts -Recurse -Force -ErrorAction SilentlyContinue

& $dotnet restore $solution --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed with exit code $LASTEXITCODE." }

& $dotnet build $solution --configuration $Configuration --no-restore --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed with exit code $LASTEXITCODE." }

& $dotnet pack (Join-Path $SdkRoot 'Retro96.Plugin.SDK.csproj') --configuration $Configuration --no-build --no-restore --nologo
if ($LASTEXITCODE -ne 0) { throw "dotnet pack failed with exit code $LASTEXITCODE." }

$dll = Join-Path $SdkRoot "artifacts\bin\$Configuration\Retro96.dll"
$nupkg = Join-Path $SdkRoot "artifacts\packages\Retro96.Plugin.SDK.1.0.0.nupkg"

if (-not (Test-Path $dll)) { throw "SDK contract was not produced: $dll" }
if (-not (Test-Path $nupkg)) { throw "SDK package was not produced: $nupkg" }

Write-Host ""
Write-Host "SDK build complete."
Write-Host "  Contract : $dll"
Write-Host "  NuGet    : $nupkg"
