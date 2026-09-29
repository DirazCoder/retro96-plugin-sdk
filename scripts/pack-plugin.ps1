[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = (Get-Location).Path,

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [string]$Output
)

$ErrorActionPreference = 'Stop'

function Get-PluginProject {
    param([string]$Directory)
    $projects = @(Get-ChildItem -LiteralPath $Directory -Filter '*.csproj' -File)
    if ($projects.Count -eq 0) { throw "No .csproj found in '$Directory'." }
    if ($projects.Count -gt 1) { throw "Expected one .csproj in '$Directory', found: $($projects.Name -join ', ')" }
    return $projects[0]
}

function Resolve-Dotnet {
    param([string]$ScriptDirectory)
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command) { return $command.Source }
    $resolved = & "$ScriptDirectory\resolve-dotnet11.ps1" | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($resolved) -or -not (Test-Path $resolved)) {
        throw 'Could not resolve a usable .NET 11 SDK executable.'
    }
    return $resolved
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)] [string]$BasePath,
        [Parameter(Mandatory)] [string]$TargetPath
    )
    $base = [System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
    $target = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = [System.Uri]$base
    $targetUri = [System.Uri]$target
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()) -replace '/', '\'
}

$pluginDirectory = [System.IO.Path]::GetFullPath($Path)
if (-not (Test-Path $pluginDirectory -PathType Container)) {
    throw "Plugin directory not found: $pluginDirectory"
}

$project = Get-PluginProject -Directory $pluginDirectory
$manifestPath = Join-Path $pluginDirectory 'plugin.json'
if (-not (Test-Path $manifestPath -PathType Leaf)) {
    throw "Manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
foreach ($required in @('id', 'name', 'version', 'apiVersion', 'assembly', 'entryPoint')) {
    if ([string]::IsNullOrWhiteSpace([string]$manifest.$required)) {
        throw "plugin.json is missing required field '$required'."
    }
}
if ([int]$manifest.apiVersion -ne 1) {
    throw "Unsupported apiVersion '$($manifest.apiVersion)'. This SDK supports apiVersion 1."
}

$assembly = [string]$manifest.assembly
if (-not $assembly.StartsWith('lib/', [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "plugin.json assembly must be under lib/ (for example lib/$($project.BaseName).dll)."
}

$dist = Join-Path $pluginDirectory 'dist'
$buildOutput = Join-Path $dist 'build'
$packageLib = Join-Path $dist 'lib'
$packageOutput = Join-Path $dist 'packages'

Remove-Item $dist -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $buildOutput, $packageLib, $packageOutput | Out-Null

$dotnet = Resolve-Dotnet -ScriptDirectory $PSScriptRoot

& $dotnet build $project.FullName --configuration $Configuration --nologo "-p:BaseOutputPath=$($buildOutput.TrimEnd('\'))\" "-p:BaseIntermediateOutputPath=$($dist.TrimEnd('\'))\obj\"
if ($LASTEXITCODE -ne 0) { throw "Plugin build failed with exit code $LASTEXITCODE." }

$assemblyLeaf = [System.IO.Path]::GetFileName(($assembly.Substring(4) -replace '/', '\'))
$builtCandidates = @(Get-ChildItem -LiteralPath $buildOutput -Recurse -Filter $assemblyLeaf -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/](ref|refint)[\\/]' })

if ($builtCandidates.Count -ne 1) {
    if ($builtCandidates.Count -eq 0) {
        throw "Built plugin assembly '$assemblyLeaf' was not found under '$buildOutput'."
    }
    throw "Found multiple '$assemblyLeaf' files under '$buildOutput'."
}
$builtAssembly = $builtCandidates[0].FullName
$buildDirectory = Split-Path $builtAssembly -Parent

# New 1.0.0 contract: the public API assembly is Retro96.dll. Never ship the
# SDK contract assembly inside a plugin package.
$references = [System.Reflection.Assembly]::LoadFile($builtAssembly).GetReferencedAssemblies()
if ($references | Where-Object { $_.Name -eq 'Retro96.Plugin.SDK' }) {
    throw "The plugin references the obsolete 'Retro96.Plugin.SDK' assembly identity. Rebuild against the 1.0.0 SDK contract (Retro96.dll)."
}

$runtimeFiles = @(Get-ChildItem -LiteralPath $buildDirectory -Recurse -File |
    Where-Object {
        $_.Name -notin @('Retro96.dll', 'Retro96.Plugin.SDK.dll') -and
        $_.Extension -notin @('.pdb') -and
        $_.FullName -notmatch '[\\/](ref|refint)[\\/]'
    })
if ($runtimeFiles.Count -eq 0) { throw "No runtime files were produced in '$buildOutput'." }

foreach ($file in $runtimeFiles) {
    $relative = Get-RelativePath -BasePath $buildDirectory -TargetPath $file.FullName
    $destination = Join-Path $packageLib $relative
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
}

$manifestAssembly = Join-Path $packageLib (($assembly.Substring(4)) -replace '/', '\')
if (-not (Test-Path $manifestAssembly -PathType Leaf)) {
    throw "Manifest assembly '$assembly' was not staged in '$packageLib'."
}

if ([string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $packageOutput "$($manifest.id)-$($manifest.version).r96p"
} elseif (-not [System.IO.Path]::IsPathRooted($Output)) {
    $Output = Join-Path $pluginDirectory $Output
}
$outputPath = [System.IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path (Split-Path $outputPath -Parent) | Out-Null
Remove-Item $outputPath -Force -ErrorAction SilentlyContinue

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("retro96-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'lib') | Out-Null

try {
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stage 'plugin.json')
    Copy-Item -LiteralPath $packageLib -Destination (Join-Path $stage 'lib') -Recurse -Force

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $outputPath)
}
finally {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Plugin packaged."
Write-Host "  Project : $($project.FullName)"
Write-Host "  Build   : $buildDirectory"
Write-Host "  Runtime : $packageLib"
Write-Host "  Package : $outputPath"
