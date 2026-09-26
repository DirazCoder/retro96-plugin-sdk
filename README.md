# Retro96 Plugin SDK

The **Retro96 Plugin SDK** is a standalone C#/.NET 11 SDK for authoring Retro96 `.r96p` plugins. The browser host does **not** contain the SDK source project and does **not** build the SDK as part of the host solution.

A plugin package is a ZIP with this shape:

```text
Example.r96p
├── plugin.json
└── lib/
    └── ExamplePlugin.dll
```

The SDK is an original Retro96 API. It does not bundle, reuse, or redistribute Netscape/NPAPI source or headers. The historical model that inspired the separation is the same broad idea: publish a stable SDK contract, let extension authors compile their own code against it, and keep the browser implementation separate.

## Requirements

- Windows
- .NET 11 SDK (the pinned version is declared in `Retro96.Plugin.SDK/global.json`)
- C# / normal .NET class-library tooling

### SDK installation behavior

The SDK build scripts first ask the `dotnet` executable already on `PATH` to resolve the pinned `global.json`. If that succeeds, that installed SDK is used. If no usable SDK is available, `bootstrap-dotnet11.ps1` downloads the pinned .NET 11 SDK into the repository's `.dotnet` directory as a fallback.

## Build the SDK

From the repository root:

```powershell
.\Retro96.Plugin.SDKuild.ps1
```

The build script:

1. resolves an existing compatible `dotnet` first;
2. restores and builds the SDK and sample plugin;
3. explicitly packs the SDK NuGet package (normal `dotnet build` does not require packaging files);
4. verifies `Retro96.Plugin.SDK.dll` exists;
5. installs the public contract DLL to `%LOCALAPPDATA%\Retro96\PluginSDK\Retro96.Plugin.SDK.dll` for the Retro96 host.

Artifacts:

```text
Retro96.Plugin.SDKrtifactsin\Release\Retro96.Plugin.SDK.dll
Retro96.Plugin.SDKrtifacts\packages\Retro96.Plugin.SDK.1.0.0.nupkg
examples\Retro96.SamplePlugin\dist\lib\Retro96.SamplePlugin.dll
```

## Retro96 host consumption

The Retro96 host is a separate project. It does not build or contain the SDK source. After running `build.ps1`, the SDK package is available from `%LOCALAPPDATA%\Retro96\PluginSDK\packages`; the host restores `Retro96.Plugin.SDK` from that local feed. This keeps SDK compilation and plugin compilation entirely in the SDK repository.

A normal SDK `dotnet build` does not require package generation or a README to exist. Use `dotnet pack` (or `build.ps1`) when you actually want the NuGet package.

## Authoring a plugin

Reference the SDK project while developing inside this repository:

```xml
<ProjectReference Include="..\..\Retro96.Plugin.SDK\Retro96.Plugin.SDK.csproj" />
```

Or consume the packed `Retro96.Plugin.SDK` NuGet package / built DLL from another repository.

Your plugin implements:

```csharp
public sealed class MyPlugin : IRetro96Plugin
{
    public void Initialize(IRetro96PluginHost host)
    {
        // register features through the public host interfaces
    }

    public void Dispose()
    {
    }
}
```

Do **not** reference `Retro96.csproj`. Plugins compile against the SDK contract only.

## Manifest

`plugin.json` declares the plugin identity, API version, DLL, entry point, and requested permissions:

```json
{
  "id": "example.plugin",
  "name": "Example Plugin",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Example Author",
  "description": "Example Retro96 plugin.",
  "assembly": "lib/ExamplePlugin.dll",
  "entryPoint": "Example.Plugin",
  "permissions": ["ui", "browser.read"]
}
```

A plugin is installed disabled. The host grants only permissions explicitly requested in the manifest and approved by the user.

## API version 1

The public contract lives in `Retro96.Plugin.SDK/PluginApi.cs` under the `Retro96.Plugins` namespace.

### Browser

`IBrowserService` provides current URL/title, navigation, reload, back/forward, new-window navigation, scrolling, zoom, viewport size, origin-scoped cookies, find-in-page, and viewport PNG capture.

Permissions:

- `browser.read`
- `browser.navigate`
- `browser.windows`
- `browser.events`
- `browser.zoom`
- `browser.cookies`
- `browser.find`
- `browser.screenshot`

### User interface

`IUiService` provides File-menu items, toolbar buttons, context-menu items, status text, progress, message dialogs, input dialogs, and constrained plugin panels/widgets.

Permissions:

- `ui`
- `ui.panel`

The panel API deliberately exposes constrained widgets rather than raw WinForms controls.

### Network

`INetworkService` provides string/binary GET, string/binary POST, and a general request API with broker-controlled headers.

Permission: `network`.

### Filesystem

`IFileSystemService` is confined to the plugin's private data directory and supports text/binary read/write, existence checks, listing, deletion, and directory creation.

Permission: `filesystem`.

### Storage

`IStorageService` provides string values, key enumeration, JSON object helpers, deletion, and approximate byte usage.

Permission: `storage`.

### Events

`IEventsService` provides navigation/page-loaded events, host shutdown, focus changes, and worker-local timers.

Permission for browser events: `browser.events`. Timers are worker-local and require no additional permission.

### Clipboard

`IClipboardService` provides text read/write, clipboard-change events, image read, and image write.

Permission: `clipboard`.

### Audio

`IAudioService` provides sandbox-relative audio playback, stop, volume, looping, and completion notification.

Permission: `audio.playback`.

### Notifications

`INotificationService` provides OS notifications with an optional click callback.

Permission: `notifications`.

### File dialogs

`IDialogsService` provides sandbox-safe open/save file pickers. Open copies the chosen file into the plugin sandbox. Save streams a sandbox file to a user-selected destination; the plugin never receives the real host path.

Permission: `dialogs`.

## Permission names

```text
browser.read
browser.navigate
browser.windows
browser.events
browser.zoom
browser.cookies
browser.find
browser.screenshot
ui
ui.panel
storage
network
filesystem
clipboard
audio.playback
notifications
dialogs
```

## Sandbox model

The browser host keeps the existing sandbox architecture:

- separate plugin worker process;
- Windows AppContainer isolation;
- Job Object process/resource controls;
- named-pipe broker;
- permission checks at the worker and host broker boundaries;
- no direct host filesystem paths exposed to plugins;
- plugin API operations are serialized across the broker.

The `.r96p` package contains your compiled plugin DLL and manifest. It does not contain the browser executable or browser source.

## Build and package the sample plugin

The sample plugin is a real class library and its build always produces:

```text
examples\Retro96.SamplePlugin\dist\lib\Retro96.SamplePlugin.dll
```

To build/package it explicitly:

```powershell
.\Retro96.Plugin.SDK\pack-plugin.ps1 `
  -Project .\examples\Retro96.SamplePlugin\Retro96.SamplePlugin.csproj `
  -Manifest .\examples\Retro96.SamplePlugin\plugin.json
```

The pack script uses an installed compatible `dotnet` first and bootstraps the pinned SDK only when needed.

## Separation from the host

The Retro96 host consumes `Retro96.Plugin.SDK.dll` as a binary contract reference. The host repository does not own or build the SDK project. The SDK repository owns the SDK assembly, sample plugin, NuGet package, and `.r96p` packaging tools.

This keeps the plugin API versioned and independently buildable while preserving a stable runtime contract for the sandboxed host.
