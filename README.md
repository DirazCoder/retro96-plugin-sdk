# Retro96 Plugin SDK

A standalone C#/.NET 11 SDK for authoring Retro96 `.r96p` plugins. The browser host compiles the public contract directly into its own binary, allowing plugins to target a versioned SDK assembly (`Retro96.dll`) without requiring the host source.

A plugin package is a ZIP archive formatted as follows:

```text
Example.r96p
├── plugin.json
└── lib/
    └── ExamplePlugin.dll
```

## Requirements

* Windows
* .NET 11 SDK (version declared in `Retro96.Plugin.SDK/global.json`)
* C# / standard .NET class-library tooling

### SDK Installation

The build scripts look for a compatible `dotnet` executable on your `PATH`. If missing, `bootstrap-dotnet11.ps1` downloads the pinned .NET 11 SDK into the local `.dotnet` directory as a fallback.

## Building the SDK

Run the build script from the repository root:

```powershell
.\Retro96.Plugin.SDK\build.ps1
```

The script performs the following steps:
1. Resolves a compatible `dotnet` installation.
2. Restores and builds the SDK and sample plugins.
3. Packs the `Retro96.Plugin.SDK` NuGet package.
4. Generates the public contract assembly as `Retro96.dll`.

Outputs:

```text
Retro96.Plugin.SDK\artifacts\bin\Release\Retro96.dll
Retro96.Plugin.SDK\artifacts\packages\Retro96.Plugin.SDK.1.0.0.nupkg
examples\Retro96.SamplePlugin\dist\lib\Retro96.SamplePlugin.dll
```

## Authoring a Plugin

Reference the SDK project directly within this repository:

```xml
<ProjectReference Include="..\..\Retro96.Plugin.SDK\Retro96.Plugin.SDK.csproj"/>
```

For external repositories, reference the `Retro96.Plugin.SDK` NuGet package or the built `Retro96.dll`.

Implement `IRetro96Plugin`:

```csharp
public sealed class MyPlugin : IRetro96Plugin
{
    public void Initialize(IRetro96PluginHost host)
    {
        // Register features via host interfaces
    }

    public void Dispose()
    {
    }
}
```

Do not reference `Retro96.csproj` directly. Plugins compile strictly against the SDK contract.

## Contract Assembly Naming (`Retro96.dll`)

While the NuGet package ID is `Retro96.Plugin.SDK`, the compiled contract assembly is named `Retro96.dll`. Retro96 compiles `PluginApi.cs` directly into the host binary, matching runtime type identities across both sides.

Plugins built against pre-1.0.1 SDK revisions referenced an assembly named `Retro96.Plugin.SDK.dll` and will fail to load in current host versions. To fix this, delete your project's `bin`/`obj` folders, restore against the current SDK, rebuild, and repackage.

## Plugin Manifest (`plugin.json`)

The manifest defines identity, API version, entry point, permissions, supported MIME types, and the optional JavaScript bridge identifier:

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
  "permissions": [
    "embed.renderer",
    "embed.network",
    "embed.navigate",
    "embed.status",
    "embed.print",
    "embed.script"
  ],
  "embed_types": [
    "application/x-example"
  ],
  "script_name": "ExamplePlayer"
}
```

* `embed_types`: MIME types the plugin can render.
* `script_name`: The identifier exposed to document scripts for finding the plugin.

Plugins install disabled by default. The host grants only permissions declared in the manifest and explicitly approved by the user.

For `content.transform`, the manifest must also declare `content_transform_scopes`. Each entry has a URL glob and MIME glob; only matching responses are delivered to the plugin. Returned HTML is sanitized by the host before normal parsing.

```json
"permissions": ["content.transform"],
"content_transform_scopes": [
  { "url": "https://example.test/*", "mime": "text/html" },
  { "url": "https://example.test/docs/*", "mime": "text/*" }
]
```

`*` matches any sequence and `?` matches one character. Scope patterns are limited to 2048 characters per entry.

## Core API Services (`Retro96.Plugins`)

The public API defined in `Retro96.Plugin.SDK/PluginApi.cs` provides access to host services:

* **`IBrowserService`**: URL/title access, navigation, reloading, history, tabs, scrolling, zoom, viewport sizing, cookies, find-in-page, and PNG screenshots.  
  *Permissions*: `browser.read`, `browser.navigate`, `browser.windows`, `browser.events`, `browser.zoom`, `browser.cookies`, `browser.find`, `browser.screenshot`
* **`IUiService`**: Custom menus, toolbar items, context options, status text, progress meters, dialogs, and constrained UI panels.  
  *Permissions*: `ui`, `ui.panel`
* **`INetworkService`**: Managed HTTP GET, POST, and custom requests.  
  *Permission*: `network`
* **`IFileSystemService`**: File operations confined to the plugin's isolated data directory.  
  *Permission*: `filesystem`
* **`IStorageService`**: Key-value storage, JSON serialization helpers, and storage usage metrics.  
  *Permission*: `storage`
* **`IEventsService`**: Browser lifecycle events and worker-local timers.  
  *Permissions*: `browser.events` (timers do not require permissions)
* **`IClipboardService`**: System clipboard text and image access.  
  *Permission*: `clipboard`
* **`IAudioService`**: Audio playback, looping, and volume control.  
  *Permission*: `audio.playback`
* **`INotificationService`**: System desktop notifications with interaction callbacks.  
  *Permission*: `notifications`
* **`IDialogsService`**: Isolated file open and save dialogs.  
  *Permission*: `dialogs`

---

## Embedded Content (`IEmbeddedContentService`)

The embedded content API provides out-of-process rendering for custom media types (such as Director, QuickTime, or custom viewers).

To render embedded content, request `embed.renderer` and register handled MIME types:

```csharp
public sealed class MyEmbeddedPlugin : IRetro96Plugin
{
    public void Initialize(IRetro96PluginHost host)
    {
        host.Embeds.Register(
            new EmbeddedContentRegistration(
                new[] { "application/x-example", "application/example" },
                CreateInstance));
    }

    private static IEmbeddedContentInstance CreateInstance(
        EmbeddedContentContext context,
        IPluginByteStream stream,
        IEmbeddedContentHost contentHost,
        IEmbeddedScriptBridge script)
    {
        return new ExampleInstance(context, stream, contentHost, script);
    }

    public void Dispose() { }
}
```

### Rendering & Compositing

Plugins render frames into software pixel buffers rather than accessing native window handles (`HWND` or GDI surfaces):

```csharp
Task<EmbeddedFrameBuffer> RenderAsync(
    EmbeddedRenderRequest request,
    CancellationToken cancellationToken = default);
```

`EmbeddedFrameBuffer` supplies dimensions, stride, and BGRA-8888 premultiplied pixel data. The host composites these buffers using Skia.

### Input Handling

The host forwards input events to the plugin:

```csharp
Task HandleInputAsync(
    EmbeddedInputEvent inputEvent,
    CancellationToken cancellationToken = default);
```

Supported events: mouse movement, button states, scroll wheel, key presses, text input, and window focus changes.

### Data Streams

Source data arrives as a push-based stream with explicit flow control:

```csharp
public interface IPluginByteStream : IDisposable
{
    bool CanSeek { get; }
    long? Length { get; }
    long Position { get; }
    bool EndOfStream { get; }

    event EventHandler<EmbeddedStreamChunkEventArgs>? ChunkReceived;

    Task RequestMoreAsync(int maxBytes, CancellationToken cancellationToken = default);
}
```

Plugins request additional bytes explicitly via `RequestMoreAsync` to prevent buffering large resources unnecessarily.

If `CanSeek` is true, cast the stream to `IPluginSeekableByteStream`:

```csharp
public interface IPluginSeekableByteStream : IPluginByteStream
{
    Task<EmbeddedSeekResult> SeekAsync(
        long offset, 
        SeekOrigin origin, 
        CancellationToken cancellationToken = default);
}
```

### Additional Embedded Capabilities

* **Network**: Fetch secondary resources via `OpenStreamAsync` (requires `embed.network`). Returns a streamed `IPluginByteStream`.
* **Context**: Inspect `CurrentUrl` and `UserAgent` via the host context.
* **Navigation**: Trigger host navigation using `RequestNavigationAsync` (requires `embed.navigate`).
* **Status**: Set host status bar text via `SetStatusAsync` (requires `embed.status`).
* **Printing**: Render print frames at target DPI via `RenderAsync` when `EmbeddedRenderRequest.IsPrint` is true (requires `embed.print`).

---

## Embedded JavaScript Bridge

Request `embed.script` to enable asynchronous interop between page scripts and the plugin over the named-pipe broker.

### Type System (`JsValue`)

The bridge supports flat, strongly-typed values:
* Primitives: `null`, `string`, `number`, `bool`
* Flat arrays of primitives
* Flat key-value dictionaries of primitives

Nested structures, function references, DOM nodes, and raw objects are unsupported.

```csharp
var args = new[] { JsValue.From("play"), JsValue.From(10.0), JsValue.From(true) };

var options = JsValue.FromObject(new Dictionary<string, JsValue>
{
    ["loop"] = JsValue.From(true),
    ["volume"] = JsValue.From(0.75)
});
```

### Exposing Plugin Methods

Register handlers in `IEmbeddedScriptBridge.Methods`:

```csharp
script.Methods["getVersion"] = async args => JsValue.From("0.1");

script.Methods["add"] = async args =>
{
    var a = args[0].NumberValue;
    var b = args[1].NumberValue;
    return JsValue.From(a + b);
};
```

Page JavaScript executes these methods asynchronously through the host's embed collection:

```javascript
const plugin = document.embeds[0];
const version = await plugin.call("getVersion");
```

### Invoking Page Functions

Call page-defined functions via `CallPageFunction`:

```csharp
JsValue result = await script.CallPageFunction(
    "onDirectorEvent",
    new[] { JsValue.From("started"), JsValue.From(1.0) });
```

---

## Permission Reference

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

embed.renderer
embed.network
embed.navigate
embed.status
embed.print
embed.script
page.read
network.rules
protocol
content.transform
page.style
tabs
history
bookmarks
downloads
omnibox
settings
ui.extras
embed.audio
embed.extras
```

---

## Security & Isolation Model

Plugins execute inside a sandboxed environment:
* Out-of-process isolation via AppContainer and Windows Job Objects.
* IPC mediated via a named-pipe broker enforcing permission checks on both ends.
* No direct access to host filesystem paths, raw network sockets, or window handles.
* Frame buffers composited host-side via Skia.

---

## Packaging Examples

To package a plugin using `pack-plugin.ps1`:

```powershell
# Director Stub Example
.\Retro96.Plugin.SDK\pack-plugin.ps1 `
  -Project .\examples\Retro96.DirectorStubPlugin\Retro96.DirectorStubPlugin.csproj `
  -Manifest .\examples\Retro96.DirectorStubPlugin\plugin.json

# Sample Plugin Example
.\Retro96.Plugin.SDK\pack-plugin.ps1 `
  -Project .\examples\Retro96.SamplePlugin\Retro96.SamplePlugin.csproj `
  -Manifest .\examples\Retro96.SamplePlugin\plugin.json
```

Output assemblies compile to their respective `dist/lib/` directories and package into `.r96p` archives.