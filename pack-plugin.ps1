
param(
    [Parameter(Mandatory=$true)][string]$Project,
    [Parameter(Mandatory=$true)][string]$Manifest,
    [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$Dotnet = & "$PSScriptRoot\resolve-dotnet11.ps1" | Select-Object -Last 1
if ([string]::IsNullOrWhiteSpace($Dotnet) -or -not (Test-Path $Dotnet)) {
    throw "Could not resolve a usable .NET SDK executable."
}

& $Dotnet build (Resolve-Path $Project) -c Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$manifestPath = (Resolve-Path $Manifest).Path
$manifestData = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json

$projectPath = (Resolve-Path $Project).Path
$projectDirectory = Split-Path $projectPath -Parent
$assemblyRelative = [string]$manifestData.assembly
if ([string]::IsNullOrWhiteSpace($assemblyRelative)) {
    throw "plugin.json must contain an 'assembly' path."
}

$assemblyCandidates = @(
    (Join-Path $projectDirectory $assemblyRelative.Replace('/','\')),
    (Join-Path $projectDirectory (Join-Path 'dist' $assemblyRelative.Replace('/','\'))),
    (Join-Path $projectDirectory (Join-Path 'bin' (Join-Path 'Release' $assemblyRelative.Replace('/','\'))))
)
$assemblyPath = $assemblyCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $assemblyPath) {
    throw "Plugin assembly not found. Checked: $($assemblyCandidates -join ', ')"
}

if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $projectDirectory "$($manifestData.id)-$($manifestData.version).r96p"
}

$outputDirectory = [System.IO.Path]::GetFullPath((Split-Path $Output -Parent))
$outputFile = Join-Path $outputDirectory (Split-Path $Output -Leaf)
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$staging = Join-Path $env:TEMP ("retro96-plugin-" + [guid]::NewGuid().ToString('N'))
try {
    $assemblyDestination = Join-Path $staging $assemblyRelative.Replace('/','\')
    New-Item -ItemType Directory -Force -Path (Split-Path $assemblyDestination -Parent) | Out-Null
    Copy-Item $manifestPath (Join-Path $staging 'plugin.json')
    Copy-Item $assemblyPath $assemblyDestination

    if (Test-Path $outputFile) { Remove-Item -Force $outputFile }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $outputFile, [System.IO.Compression.CompressionLevel]::Optimal, $false)
}
finally {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $staging
}
Write-Host "Created plugin package: $outputFile"
