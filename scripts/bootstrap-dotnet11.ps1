param(
    [string]$InstallDir = (Join-Path $PSScriptRoot '.dotnet')
)

$ErrorActionPreference = 'Stop'
$SdkVersion = '11.0.100-rc.1.26425.128'
$DotnetExe = Join-Path $InstallDir 'dotnet.exe'

if (-not (Test-Path $DotnetExe)) {
    Write-Host "Retro96 Plugin SDK: downloading .NET $SdkVersion..."
    $Installer = Join-Path $env:TEMP 'retro96-dotnet-install.ps1'
    Invoke-WebRequest -UseBasicParsing 'https://dot.net/v1/dotnet-install.ps1' -OutFile $Installer
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Installer -Version $SdkVersion -InstallDir $InstallDir -NoPath
        if ($LASTEXITCODE -ne 0) { throw "dotnet-install.ps1 exited with code $LASTEXITCODE" }
    }
    finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $Installer
    }
}

if (-not (Test-Path $DotnetExe)) {
    throw "The .NET 11 SDK was not installed at '$InstallDir'."
}

& $DotnetExe --info
