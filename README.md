# Retro96 Plugin SDK

The Retro96 Plugin SDK is the **public C# contract only**: `PluginApi.cs`, the SDK project, and the authoring/packaging scripts. Example plugins live under `examples/`, but they are standalone projects and are **not part of the SDK solution**.

## Current contract

SDK version: **1.0.0**  
API version: **1**  
Target framework: **.NET 11**  
Contract assembly: **`Retro96.dll`**

The 1.0.0 contract is a breaking change from older plugin builds. Plugins must be rebuilt against this SDK. Do not copy `Retro96.dll` or `Retro96.Plugin.SDK.dll` into a plugin package; the host provides the contract assembly.

`PluginApi.cs` is the source of truth for the public API and is intentionally kept unchanged by the SDK tooling cleanup.

## Requirements

- Windows or another environment with a compatible .NET 11 SDK
- PowerShell 7+ for the helper scripts

The repository includes `global.json` with the tested .NET 11 SDK selection. When `dotnet` is not on `PATH`, the scripts can resolve the local .NET 11 bootstrap helper.

## Build the SDK

From the SDK root:

```powershell
.\scripts\build.ps1
```

This builds **only the SDK project** from `Retro96.Plugin.SDK.sln` and creates:

```text
artifacts/
├── bin/
│   └── Release/
│       ├── Retro96.dll
│       └── Retro96.xml
├── obj/
└── packages/
    └── Retro96.Plugin.SDK.1.0.0.nupkg
```

The examples are deliberately not built by this command.

## Create a new plugin

From the SDK root:

```powershell
.\scripts\new-plugin.ps1 MyPlugin
```

That creates:

```text
examples/
└── MyPlugin/
    ├── MyPlugin.csproj
    ├── MyPlugin.cs
    ├── plugin.json
    └── README.md
```

The generated project references the SDK contract directly, targets the same .NET 11 framework, and keeps its build output under its own `dist/` folder.

## Build and package a plugin

From the SDK root:

```powershell
.\scripts\pack-plugin.ps1 .\examples\MyPlugin
```

Or from inside the plugin folder:

```powershell
..\..\scripts\pack-plugin.ps1
```

You do not need to type the `.csproj` or `plugin.json` paths. The pack script discovers them automatically.

Plugin output is isolated to the plugin folder:

```text
dist/
├── build/      # raw compiler output
├── obj/        # intermediate build files
├── lib/        # runtime files staged for the package
└── packages/   # final .r96p package
```

The package layout is:

```text
MyPlugin-1.0.0.r96p
├── plugin.json
└── lib/
    ├── MyPlugin.dll
    ├── MyPlugin.deps.json
    └── <other runtime dependencies>
```

The pack script removes the contract assemblies from package contents and rejects plugins still referencing the obsolete `Retro96.Plugin.SDK` assembly identity.

## Project setup for external plugins

A plugin project needs only a normal class-library project plus a project or package reference to the SDK. The simplest repository-local reference is:

```xml
<ItemGroup>
  <ProjectReference Include="..\..\Retro96.Plugin.SDK.csproj">
    <Private>false</Private>
  </ProjectReference>
</ItemGroup>
```

`Private=false` prevents the shared `Retro96.dll` contract from being copied beside the plugin. The host owns that assembly at runtime.

## Minimal plugin

```csharp
using Retro96.Plugins;

namespace MyPlugin;

public sealed class Plugin : IRetro96Plugin
{
    public void Initialize(IRetro96PluginHost host)
    {
        host.Log.Info("MyPlugin initialized.");
    }

    public void Dispose()
    {
    }
}
```

And the corresponding manifest:

```json
{
  "id": "myplugin",
  "name": "MyPlugin",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "",
  "description": "My Retro96 plugin.",
  "assembly": "lib/MyPlugin.dll",
  "entryPoint": "MyPlugin.Plugin",
  "permissions": []
}
```

## Manifest notes

`plugin.json` is the runtime manifest. The current contract uses these JSON names for the fields introduced/changed by the current API, including:

- `optional_permissions`
- `embed_types`
- `content_transform_scopes`
- `script_name`
- `min_host_version`

The manifest `apiVersion` is currently `1` and plugin package versions in this SDK are `1.0.0` by default.

For embedded content, every MIME type registered through `host.Embeds.Register(...)` must also be declared in `embed_types`. The JavaScript bridge uses the typed `JsValue` model from `PluginApi.cs`; arrays and objects are intentionally flat.

## Examples

The examples are real plugins, but they are kept separate from the SDK solution so a normal SDK build stays clean:

- `Retro96.SamplePlugin` — menu command, page events, and logging.
- `Retro96.TransformSamplePlugin` — scoped `content.transform` registration.
- `Retro96.DirectorStubPlugin` — embedded-content registration, streamed bytes, rendering, input, and the async JavaScript bridge.

Build any one example with the same `pack-plugin.ps1` command shown above.
