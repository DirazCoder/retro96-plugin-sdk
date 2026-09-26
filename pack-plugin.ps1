[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Project,

    [Parameter(Mandatory = $true)]
    [string]$Manifest,

    [string]$Output
)

$ErrorActionPreference = 'Stop'

$projectPath = [System.IO.Path]::GetFullPath($Project)
$manifestPath = [System.IO.Path]::GetFullPath($Manifest)
$projectDirectory = Split-Path $projectPath -Parent

if (-not (Test-Path $projectPath)) {
    throw "Project file not found: $projectPath"
}
if (-not (Test-Path $manifestPath)) {
    throw "Manifest file not found: $manifestPath"
}

$manifestData = Get-Content $manifestPath -Raw | ConvertFrom-Json

# Start clean so a previously built DLL can never be mistaken for the current
# build (same reasoning as build.ps1's cleanup, generalized to any plugin project).
Remove-Item -Path (Join-Path $projectDirectory 'dist') -Recurse -Force -ErrorAction SilentlyContinue

dotnet build $projectPath -c Release
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed."
}

$assemblyRelative = $manifestData.assembly -replace '^lib/', ''
$assemblyCandidates = @(
    (Join-Path $projectDirectory $manifestData.assembly.Replace('/','\')),
    (Join-Path $projectDirectory $assemblyRelative.Replace('/','\')),
    (Join-Path $projectDirectory (Join-Path 'dist' $assemblyRelative.Replace('/','\'))),
    (Join-Path $projectDirectory (Join-Path 'dist' (Join-Path 'lib' (Split-Path $manifestData.assembly -Leaf)))),
    (Join-Path $projectDirectory (Join-Path 'bin' (Join-Path 'Release' $assemblyRelative.Replace('/','\'))))
)
$assemblyPath = $assemblyCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $assemblyPath) {
    throw "Plugin assembly not found. Checked: $($assemblyCandidates -join ', ')"
}

# Reject binaries compiled against the pre-1.0.1 SDK assembly identity. Those
# plugins request `Retro96.Plugin.SDK` at runtime, while the host intentionally
# shares its public contract from the `Retro96` host assembly. They cannot be
# safely rebound by AssemblyLoadContext.
$references = [System.Reflection.Assembly]::LoadFile($assemblyPath).GetReferencedAssemblies()
if ($references | Where-Object { $_.Name -eq 'Retro96.Plugin.SDK' }) {
    throw "The plugin DLL references the obsolete `Retro96.Plugin.SDK` assembly identity. Clean/rebuild the plugin against the current Retro96 Plugin SDK 1.0.1 before packaging."
}

if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $projectDirectory "$($manifestData.id)-$($manifestData.version).r96p"
}

$outputDirectory = [System.IO.Path]::GetFullPath((Split-Path $Output -Parent))
$outputFile = Join-Path $outputDirectory (Split-Path $Output -Leaf)
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stagingDir 'lib') | Out-Null

Copy-Item $manifestPath (Join-Path $stagingDir 'plugin.json')
Copy-Item $assemblyPath (Join-Path $stagingDir (Join-Path 'lib' (Split-Path $manifestData.assembly -Leaf)))

if (Test-Path $outputFile) {
    Remove-Item $outputFile -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $outputFile)

Remove-Item $stagingDir -Recurse -Force

Write-Host "Packaged plugin: $outputFile"