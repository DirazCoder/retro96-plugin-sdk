# Retro96 Plugin SDK

A standalone C#/.NET 11 SDK for authoring Retro96 `.r96p` plugins. The browser host doesn't contain this SDK's source and doesn't build it as part of the host solution — plugin authors compile against a separate, versioned contract instead of the host's own code.

A plugin package is a ZIP:

```text
Example.r96p
├── plugin.json
└── lib/
    └── ExamplePlugin.dll
```

## Requirements

- Windows
- .NET 11 SDK (pinned version declared in `Retro96.Plugin.SDK/global.json`)
- C# / normal .NET class-library tooling

### How SDK installation works

The build scripts first ask whatever `dotnet` is already on `PATH` to resolve the pinned `global.json`. If that works, they use it. If nothing usable is installed, `bootstrap-dotnet11.ps1` downloads the pinned .NET 11 SDK into the repo's `.dotnet` directory as a fallback.

## Building the SDK

From the repository root:

```powershell
.\Retro96.Plugin.SDK\build.ps1
```

What it does:

1. resolves an existing compatible `dotnet` first
2. restores and builds the SDK and sample plugin
3. explicitly packs the SDK NuGet package (a plain `dotnet build` won't produce packaging files on its own)
4. verifies `Retro96.dll` exists
5. builds the public contract assembly as `Retro96.dll` — the host already ships the matching contract, so plugins compile against this instead

Artifacts:

```text
Retro96.Plugin.SDK\artifacts\bin\Release\Retro96.dll
Retro96.Plugin.SDK\artifacts\packages\Retro96.Plugin.SDK.1.0.0.nupkg
examples\Retro96.SamplePlugin\dist\lib\Retro96.SamplePlugin.dll
```

## Authoring a plugin

Reference the SDK project directly if you're developing inside this repo:

```xml
<ProjectReference Include="..\..\Retro96.Plugin.SDK\Retro96.Plugin.SDK.csproj" />
```

Otherwise, consume the packed `Retro96.Plugin.SDK` NuGet package or the built DLL from another repository.

Implement the plugin interface:

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

Don't reference `Retro96.csproj` directly — plugins compile against the SDK contract only.

## Manifest

`plugin.json` declares identity, API version, the DLL, entry point, and requested permissions:

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

Plugins install disabled. The host only grants permissions that are both requested in the manifest and approved by the user.

## Why the contract assembly is named `Retro96.dll`

The NuGet package ID is `Retro96.Plugin.SDK`, but the compiled contract assembly is `Retro96.dll` on purpose. Retro96 compiles the same public `PluginApi.cs` contract straight into its host assembly, so both sides share one runtime type identity without the host needing to build or install the SDK project itself.

Plugins built against pre-1.0.1 SDK revisions may still reference an assembly literally named `Retro96.Plugin.SDK`. Those binaries don't work with the current host contract — clean-rebuild them: delete the plugin project's `bin`/`obj`, restore against the current SDK, rebuild, and repackage.

The build script clears its artifact and sample-plugin output directories before every build so a stale contract DLL can't get reused by accident. The pack script also rejects any DLL that still references the old assembly name.

## API version 1

The public contract lives in `Retro96.Plugin.SDK/PluginApi.cs`, under the `Retro96.Plugins` namespace.

### Browser — `IBrowserService`

Current URL/title, navigation, reload, back/forward, new-window navigation, scrolling, zoom, viewport size, origin-scoped cookies, find-in-page, viewport PNG capture.

Permissions: `browser.read`, `browser.navigate`, `browser.windows`, `browser.events`, `browser.zoom`, `browser.cookies`, `browser.find`, `browser.screenshot`

### User interface — `IUiService`

File-menu items, toolbar buttons, context-menu items, status text, progress, message dialogs, input dialogs, and constrained plugin panels/widgets — deliberately not raw WinForms controls, since a plugin panel shouldn't be able to do anything the sandbox model doesn't already account for.

Permissions: `ui`, `ui.panel`

### Network — `INetworkService`

String/binary GET, string/binary POST, and a general request API with broker-controlled headers.

Permission: `network`

### Filesystem — `IFileSystemService`

Confined to the plugin's private data directory: text/binary read/write, existence checks, listing, deletion, directory creation.

Permission: `filesystem`

### Storage — `IStorageService`

String values, key enumeration, JSON object helpers, deletion, approximate byte usage.

Permission: `storage`

### Events — `IEventsService`

Navigation/page-loaded events, host shutdown, focus changes, worker-local timers. Browser events need `browser.events`; timers are worker-local and don't need any extra permission.

### Clipboard — `IClipboardService`

Text read/write, clipboard-change events, image read/write.

Permission: `clipboard`

### Audio — `IAudioService`

Sandbox-relative audio playback, stop, volume, looping, completion notification.

Permission: `audio.playback`

### Notifications — `INotificationService`

OS notifications with an optional click callback.

Permission: `notifications`

### File dialogs — `IDialogsService`

Sandbox-safe open/save pickers. Open copies the chosen file into the plugin sandbox. Save streams a sandbox file out to a user-picked destination — the plugin never sees the real host path either way.

Permission: `dialogs`

## All permission names

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

The host isolates plugins with:

- a separate plugin worker process
- Windows AppContainer isolation
- Job Object process/resource controls
- a named-pipe broker
- permission checks at both the worker and host broker boundaries
- no direct host filesystem paths exposed to plugins
- all plugin API calls serialized across the broker

A `.r96p` package contains your compiled plugin DLL and manifest — nothing else. It doesn't and can't contain the browser executable or browser source.

## Building and packaging the sample plugin

The sample plugin is a real class library. Building it always produces:

```text
examples\Retro96.SamplePlugin\dist\lib\Retro96.SamplePlugin.dll
```

To build/package it explicitly:

```powershell
.\Retro96.Plugin.SDK\pack-plugin.ps1 `
  -Project .\examples\Retro96.SamplePlugin\Retro96.SamplePlugin.csproj `
  -Manifest .\examples\Retro96.SamplePlugin\plugin.json
```

The pack script uses an installed compatible `dotnet` if one's available, and only bootstraps the pinned SDK when it has to.

## Why this is a separate repo from the host

The Retro96 host compiles the same public API source directly into its own assembly. This SDK builds an equivalent contract assembly, `Retro96.dll`, purely for plugin compilation — the host never restores or produces the SDK assembly, and `.r96p` packages never ship it. This SDK repo owns the contract project, the sample plugin, the NuGet package, and the `.r96p` packaging tools; the host repo owns the runtime.

That split is what lets the plugin API get versioned and built independently while the sandboxed host still gets a stable runtime contract to trust.