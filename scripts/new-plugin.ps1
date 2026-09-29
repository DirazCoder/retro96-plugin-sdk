[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9._-]{0,63}$')]
    [string]$Name,

    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'examples')
)

$ErrorActionPreference = 'Stop'
$SdkRoot = Split-Path -Parent $PSScriptRoot
$pluginDirectory = Join-Path ([System.IO.Path]::GetFullPath($OutputRoot)) $Name
$sdkProject = Join-Path $SdkRoot 'Retro96.Plugin.SDK.csproj'

if (Test-Path $pluginDirectory) {
    throw "Plugin directory already exists: $pluginDirectory"
}
if (-not (Test-Path $sdkProject -PathType Leaf)) {
    throw "SDK project not found: $sdkProject"
}

function ConvertTo-ClrName {
    param([string]$Value)
    $parts = $Value -split '[^A-Za-z0-9]+' | Where-Object { $_ }
    if ($parts.Count -eq 0) { throw "Plugin name '$Value' cannot produce a C# namespace." }
    return (($parts | ForEach-Object { $_.Substring(0,1).ToUpperInvariant() + $_.Substring(1) }) -join '')
}

$rootNamespace = ConvertTo-ClrName $Name
$projectName = $Name
$pluginId = $Name.ToLowerInvariant()
$sdkReference = [System.IO.Path]::GetRelativePath($pluginDirectory, $sdkProject)

New-Item -ItemType Directory -Force -Path $pluginDirectory | Out-Null

@"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net11.0</TargetFramework>
    <OutputType>Library</OutputType>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AssemblyName>$projectName</AssemblyName>
    <RootNamespace>$rootNamespace</RootNamespace>
    <BaseOutputPath>`$(MSBuildProjectDirectory)\dist\build\</BaseOutputPath>
    <BaseIntermediateOutputPath>`$(MSBuildProjectDirectory)\dist\obj\</BaseIntermediateOutputPath>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <Deterministic>true</Deterministic>
    <DebugSymbols>true</DebugSymbols>
    <DebugType>portable</DebugType>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="$sdkReference">
      <Private>false</Private>
    </ProjectReference>
  </ItemGroup>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $pluginDirectory "$projectName.csproj") -Encoding utf8

@"
using Retro96.Plugins;

namespace $rootNamespace;

public sealed class Plugin : IRetro96Plugin
{
    public void Initialize(IRetro96PluginHost host)
    {
        host.Log.Info("$projectName initialized.");
    }

    public void Dispose()
    {
    }
}
"@ | Set-Content -LiteralPath (Join-Path $pluginDirectory "$projectName.cs") -Encoding utf8

@"
{
  "id": "$pluginId",
  "name": "$projectName",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "",
  "description": "$projectName Retro96 plugin.",
  "assembly": "lib/$projectName.dll",
  "entryPoint": "$rootNamespace.Plugin",
  "permissions": []
}
"@ | Set-Content -LiteralPath (Join-Path $pluginDirectory 'plugin.json') -Encoding utf8

@"
# $projectName

A minimal Retro96 plugin using the 1.0.0 SDK contract.

## Build and package

From the SDK root:

```powershell
.\scripts\pack-plugin.ps1 .\examples\$projectName
```

From this plugin directory:

```powershell
..\..\scripts\pack-plugin.ps1
```

The generated output is self-contained in `dist/`:

```text
dist/
├── build/      # raw compiler output
├── lib/        # package runtime files
└── packages/   # final .r96p package
```

The SDK contract (`Retro96.dll`) is a host-provided API assembly and is not copied into plugin packages.
"@ | Set-Content -LiteralPath (Join-Path $pluginDirectory 'README.md') -Encoding utf8

Write-Host "Created Retro96 plugin: $pluginDirectory"
Write-Host "Package it with: ..\..\scripts\pack-plugin.ps1"
