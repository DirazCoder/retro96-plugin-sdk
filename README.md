# Retro96 Plugin SDK

A standalone C#/.NET 11 SDK for authoring Retro96 `.r96p` plugins.

This project contains the public plugin contract (`PluginApi.cs`), the SDK build/pack tooling, and sample plugins. The Retro96 browser host compiles the same `PluginApi.cs` directly into its own binary, so a plugin built against the SDK's contract assembly (`Retro96.dll`) shares exact type identity with the host at runtime — no host source or host binary is needed to author or build a plugin.

## Plugin Package Layout

A plugin package is a ZIP archive with the manifest at the root:

```text
Example.r96p
├── plugin.json
└── lib/
    └── ExamplePlugin.dll
```

Everything the plugin needs at runtime — dependency assemblies and the `.deps.json` produced by the build — belongs under `lib/`; the sandbox resolves plugin dependencies from the package.

Install-time package limits, enforced while extracting:

| Rule | Limit |
|---|---|
| Entries per package | 4,096 |
| Uncompressed size per entry | 256 MiB |
| Total uncompressed size | 1 GiB |
| `plugin.json` size | 1 MiB |
| Entry paths escaping the archive root | rejected |

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
        // Query host.Info, register UI/embeds/protocols, subscribe to
        // host.Events, read settings from host.Storage, ...
    }

    public void Dispose()
    {
        // Called when the plugin is disabled, updated, or shut down.
    }
}
```

Entry-point rules:

* `entryPoint` is the exact, case-sensitive, namespace-qualified type name (`Example.Plugin`). A `"Type, Assembly"` suffix is tolerated but the assembly part is ignored.
* The type must implement `IRetro96Plugin` and have a public parameterless constructor.
* `Initialize` runs once in the sandbox worker after the broker handshake. If it throws, the load fails and the error is recorded and shown in the Plugin Manager.
* The plugin assembly is loaded into its own collectible `AssemblyLoadContext`; dependencies are resolved from the package's `.deps.json`.

Do not reference `Retro96.csproj` directly. Plugins compile strictly against the SDK contract.

## Contract Assembly Naming (`Retro96.dll`)

The NuGet package ID is `Retro96.Plugin.SDK`, but the contract assembly it produces is named `Retro96.dll` — the same name as the host binary. The host compiles `PluginApi.cs` into itself, and the plugin sandbox's loader maps references to either `Retro96` or `Retro96.Plugin.SDK` onto that single host contract assembly, so the CLR sees exactly one `IRetro96Plugin` / `IRetro96PluginHost` type identity on both sides of the broker pipe.

Plugins built against pre-1.0.1 SDK revisions referenced an assembly named `Retro96.Plugin.SDK.dll`. If such a package fails to load against a current host (for example because it shipped its own stale copy of the contract DLL), delete the project's `bin`/`obj` folders, restore against the current SDK, rebuild, and repackage.

## Plugin Lifecycle

* Installing a `.r96p` registers the plugin **disabled by default**. Enable it in the Retro96 Plugin Manager (Preferences → Plugins) and grant permissions there. Loading an unpacked source folder additionally requires developer mode.
* Only permissions declared in the manifest can ever be granted; names declared under `optional_permissions` can additionally be requested at runtime (see [Permissions](#permissions)).
* **Updates** show a confirmation dialog listing the old and new DLL SHA-256 hashes, with explicit warnings when the manifest author changed or the new version is a downgrade. On update the plugin's `data/` directory is preserved, granted permissions are re-intersected with the new manifest's declared permissions, and newly requested permissions are surfaced for review.
* **Crash policy**: a plugin whose worker crashes 3 times within 5 minutes is automatically disabled. Restarts use a 1 / 2 / 5 / 10 / 30-second backoff.
* **Auditing**: every permission-gated call is recorded in a per-plugin activity log (permission, timestamp, and the network host where applicable; the last 1,000 entries are kept), viewable in the Plugin Manager.

## Plugin Manifest (`plugin.json`)

A complete example showing every optional field (most plugins use a small subset):

```json
{
  "id": "example.plugin",
  "name": "Example Plugin",
  "version": "1.2.0",
  "apiVersion": 1,
  "author": "Example Author",
  "description": "Example Retro96 plugin.",
  "website": "https://example.test/",
  "minHostVersion": "1.0.0",
  "assembly": "lib/ExamplePlugin.dll",
  "entryPoint": "Example.Plugin",
  "permissions": [
    "embed.renderer",
    "embed.network",
    "embed.status",
    "embed.print",
    "embed.script"
  ],
  "optional_permissions": [
    "embed.navigate",
    "embed.audio"
  ],
  "embed_types": [
    "application/x-example",
    "application/example"
  ],
  "content_transform_scopes": [
    { "url": "https://example.test/*", "mime": "text/html" }
  ],
  "script_name": "ExamplePlayer",
  "settings": [
    { "name": "loop", "type": "toggle", "label": "Loop playback", "default": "false" },
    { "name": "quality", "type": "select", "label": "Quality", "options": [ "low", "high" ], "default": "high" },
    { "name": "caption", "type": "text", "label": "Caption", "description": "Shown above the viewer." }
  ]
}
```

### Field Reference

| Field | Required | Constraints |
|---|---|---|
| `id` | ✔ | 1–64 chars; letters, digits, `.`, `-`, `_`. Stable identity — also the install folder name. |
| `name` | ✔ | ≤128 chars. |
| `version` | | ≤32 chars; `major.minor.patch[-prerelease]`, compared numerically (up to 4 numeric parts, each clamped to 0–999). |
| `apiVersion` | ✔ | Must be exactly `1`. |
| `author` | | ≤128 chars. Changing it between versions triggers an update warning. |
| `description` | | ≤1024 chars. |
| `website` | | ≤2048 chars. |
| `minHostVersion` | | ≤32 chars; installation is refused on older hosts. |
| `assembly` | ✔ | ≤256 chars; a path inside the package (`lib/ExamplePlugin.dll`). |
| `entryPoint` | ✔ | ≤512 chars; case-sensitive full type name implementing `IRetro96Plugin`. |
| `permissions` | | Known names only (see [Permissions](#permissions)). These are the only permissions the host will grant. |
| `optional_permissions` | | Known names; must not overlap `permissions`; requestable at runtime. |
| `embed_types` | | MIME types, 3–256 chars each, must contain `/`. At least one is required for `embed.renderer`. |
| `content_transform_scopes` | | 1–32 entries; at least one required for `content.transform`. |
| `script_name` | | A JavaScript identifier, ≤128 chars; required for `embed.script`. |
| `settings` | | ≤32 setting definitions (see below). |

### Structural Dependency Rules

* `embed.script` requires `embed.renderer` **and** a declared `script_name`.
* `embed.renderer` requires at least one `embed_types` entry.
* `content.transform` requires at least one `content_transform_scopes` entry.
* `permissions` and `optional_permissions` must be disjoint.
* MIME types passed to `Embeds.Register` must be declared in `embed_types` — the host rejects undeclared types at registration time.

### Content-Transform Scopes

Each scope entry carries a `url` glob (1–2048 chars) and a MIME-shaped `mime` glob (e.g. `text/html`, `text/*`). Matching is case-insensitive; `*` matches any sequence and `?` matches one character. Only responses matching a scope are delivered to the plugin (input capped at 8 MiB). Returned HTML (also capped at 8 MiB) is sanitized by the host — `<script>` elements, `on*` attributes, and `javascript:` / `vbscript:`-style URLs are stripped — before it is handed to the normal parser.

### Plugin Settings

Declared settings are rendered by the host in Preferences → Plugins as native toggle / text / select controls:

* Names: 1–64 chars from letters, digits, `.`, `_`, `-`; unique per plugin.
* Types: `toggle`, `text`, `select` (1–32 options, each ≤128 chars).
* `label` ≤128, `description` ≤512, `default` ≤2048 chars.

Values persist in the plugin's own storage under `settings.<name>` keys, so read them from code with the storage service:

```csharp
string quality = host.Storage.Get("settings.quality") ?? "high";
```

## Permissions

Permissions are granted only for names declared in the manifest, only after explicit user approval, and are grouped into tiers shown to the user:

| Tier | Permissions |
|---|---|
| **Sensitive** (reads user/page data; requesting one alongside `network` triggers an additional data-exfiltration warning) | `browser.read`, `browser.cookies`, `browser.screenshot`, `clipboard`, `page.read`, `content.transform`, `tabs`, `history`, `bookmarks` |
| **Elevated** | `browser.navigate`, `browser.windows`, `network`, `filesystem`, `audio.playback`, `dialogs`, `embed.renderer`, `embed.network`, `embed.navigate`, `embed.print`, `embed.script`, `network.rules`, `protocol`, `page.style`, `downloads`, `embed.audio` |
| **Standard** | `browser.events`, `ui`, `storage`, `browser.zoom`, `browser.find`, `ui.panel`, `notifications`, `embed.status`, `omnibox`, `settings`, `ui.extras`, `embed.extras` |

### Optional Permissions and Runtime Requests

Permissions listed under `optional_permissions` can be requested while the plugin runs; the host shows the user a consent prompt with the permission's risk notes:

```csharp
if (!host.HasPermission(PluginPermission.PageRead))
{
    bool granted = await host.RequestPermissionAsync("page.read");
}
```

Requests for names not declared in `optional_permissions` are refused outright. Grants are pushed to the running plugin live (they take effect immediately; no restart needed).

## Host API Surface

`IRetro96PluginHost` exposes the following services. Every call crosses the sandbox broker and is permission-checked on **both** ends — calling a service without its permission throws `SecurityException`.

| Property | Interface | Permission(s) | Highlights |
|---|---|---|---|
| `Browser` | `IPluginBrowser` | `browser.read`, `browser.navigate`, `browser.windows`, `browser.zoom`, `browser.cookies`, `browser.find`, `browser.screenshot` | Current URL/title, navigate/reload/back/forward, open window, scroll, zoom get/set, cookies, find-in-page, viewport size, PNG screenshot. |
| `Page` | `IPluginPageRead` | `page.read` | Page text (capped at 512 KiB), links (≤2000), current selection. |
| `Ui` | `IPluginUi` | `ui` (+ `ui.panel` for panels) | File-menu items, toolbar buttons, context-menu entries, status text, progress meter, message/input dialogs, widget panels (labels, buttons, text boxes, checkboxes, list boxes). |
| `UiExtras` | `IPluginUiExtras` | `ui.extras` | Toolbar buttons with PNG icon and menu placement, status badge, keyboard shortcuts (conflicts with built-ins or other plugins are rejected and reported). |
| `Storage` | `IPluginStorage` | `storage` | String key/value store with JSON object helpers (`GetObject`/`SetObject`) and used-byte reporting; also holds manifest setting values. |
| `FileSystem` | `IPluginFileSystem` | `filesystem` | Read/write/list/delete, strictly confined to the plugin's private data directory. |
| `Network` | `IPluginNetwork` | `network` | Brokered HTTP GET/POST/custom requests, plus streamed (`IPluginNetworkResponse`) variants. |
| `NetworkRules` | `IPluginNetworkRules` | `network.rules` | Up to 100 declarative block / redirect / strip-header rules, evaluated host-side (the plugin never sees live requests). |
| `Protocols` | `IPluginProtocols` | `protocol` | Register a custom URL scheme; response bodies up to 32 MiB and are parsed by the normal host renderer. |
| `ContentTransform` | `IPluginContentTransform` | `content.transform` | Rewrite HTML responses matching the manifest scopes; output is sanitized before parsing. |
| `PageStyle` | `IPluginPageStyle` | `page.style` | Inject CSS (≤64 KiB; `url()`, `@import`, `-moz-binding`, `behavior` are stripped). |
| `Tabs` | `IPluginTabs` | `tabs` | Tab URL/title summaries and a `BeforeNavigate` allow/cancel/redirect decision with a 750 ms budget. |
| `History` | `IPluginHistory` | `history` | Capped history search (≤100 results). |
| `Bookmarks` | `IPluginBookmarks` | `bookmarks` | List (≤500), add, and remove bookmarks. |
| `Downloads` | `IPluginDownloads` | `downloads` | Host-validated HTTP(S) downloads into the plugin data directory, with progress events. |
| `Omnibox` | `IPluginOmnibox` | `omnibox` | Register an address-bar keyword returning up to 8 suggestions. |
| `Clipboard` | `IPluginClipboard` | `clipboard` | Text and PNG image get/set, plus change notification. |
| `Events` | `IPluginEvents` | `browser.events` (clipboard/audio events require `clipboard` / `audio.playback`) | Navigation, page-load, title, load-progress, zoom, focus, and shutdown events; worker-local timers. |
| `Audio` | `IPluginAudio` | `audio.playback` | Play files from the data directory or raw PCM; volume, loop, completion event. |
| `Notifications` | `IPluginNotifications` | `notifications` | Notifications with optional click callbacks. |
| `Dialogs` | `IPluginDialogs` | `dialogs` | Open/save file pickers scoped to the plugin data directory. |
| `Embeds` | `IPluginEmbeddedContentService` | `embed.renderer` (+ per-capability embed permissions) | Embedded content registration — see below. |
| `Log` | `IPluginLogger` | — | Info/warn/error lines appended to the plugin's log file. |
| `Info` | `IPluginHostInfo` | — | Host version, API version, capability query (`IsSupported`), theme, locale, DPI. |

The host object itself also exposes `Manifest`, `GrantedPermissions`, `HasPermission(permission)`, and `RequestPermissionAsync(name)`.

Timers need no permission: `host.Events.CreateTimer(TimeSpan, callback)` runs entirely inside the plugin worker.

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

`EmbeddedContentContext` carries the MIME type, source URL, current page URL, user agent, the initial width/height, and `Parameters` — the attributes of the `<embed>` element as a dictionary.

Every MIME type passed to `Register` must be declared in the manifest's `embed_types`.

### Rendering & Compositing

Plugins render frames into software pixel buffers rather than accessing native window handles (`HWND` or GDI surfaces):

```csharp
Task<EmbeddedFrameBuffer> RenderAsync(
    EmbeddedRenderRequest request,
    CancellationToken cancellationToken = default);
```

* While an embed is visible, the host requests frames continuously (~30 fps). Each `RenderAsync` call must complete within **~1 second** or the call times out — keep rendering synchronous and fast.
* The frame must match the requested width and height, use a stride of at least `width * 4`, and carry exactly `stride * height` bytes of BGRA-8888 premultiplied pixel data. Call `frame.Validate()` before returning; malformed frames are rejected.
* Print rendering arrives as `EmbeddedRenderRequest.IsPrint = true` with a target DPI (requires `embed.print`).
* The host composites the buffers into the page using Skia.

### Input Handling

The host forwards input events to the plugin:

```csharp
Task HandleInputAsync(
    EmbeddedInputEvent inputEvent,
    CancellationToken cancellationToken = default);
```

Supported events: mouse move, mouse down/up, mouse wheel, key down/up, text input, and focus gained/lost. Modifier state (Shift/Ctrl/Alt/Meta) and coordinates arrive with each event.

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

* The host delivers data in chunks of at most 1 MiB, but only after the plugin asks: call `RequestMoreAsync(maxBytes)` and consume chunks from the `ChunkReceived` event. This keeps large media from being buffered wholesale.
* If `CanSeek` is true, cast to `IPluginSeekableByteStream` and use `SeekAsync(offset, origin)`; seeking resets any outstanding flow-control credit.

### Additional Embedded Capabilities

* **Network** — fetch secondary resources via `contentHost.OpenStreamAsync` (requires `embed.network`); returns the same streamed `IPluginByteStream` type over the brokered network path.
* **Navigation** — trigger host navigation with `RequestNavigationAsync` (requires `embed.navigate`); limited to `http`, `https`, `file`, and `about` URLs.
* **Status** — set host status bar text via `SetStatusAsync` (requires `embed.status`).
* **Audio** — push PCM with `PushAudioAsync` (requires `embed.audio`): 8–48 kHz, 1–2 channels, signed 16-bit LE or float32 LE, ≤1 MiB per push, byte count aligned to whole frames. Pushed audio starts **muted** and is unmuted after the user interacts with the embed; use `SetMutedAsync` for explicit control. The host mixes all plugin audio.
* **Extras** — set the embed cursor from a fixed set via `SetCursorAsync`, and receive visibility, pause, and resize notifications (requires `embed.extras`).

---

## Embedded JavaScript Bridge

Request `embed.script` (which requires `embed.renderer` and a declared `script_name`) to enable asynchronous interop between page scripts and the plugin over the named-pipe broker.

### Type System (`JsValue`)

The bridge supports flat, strongly-typed values:

* Primitives: `null`, `string`, `number`, `bool` — numbers must be finite (NaN/Infinity are rejected).
* Flat arrays of primitives (≤4096 elements).
* Flat key-value dictionaries of primitives (≤4096 entries, non-empty keys).

Nested structures, function references, DOM nodes, and raw objects are unsupported — these limits are enforced in both directions.

```csharp
var args = new[] { JsValue.From("play"), JsValue.From(10.0), JsValue.From(true) };

var options = JsValue.FromObject(new Dictionary<string, JsValue>
{
    ["loop"] = JsValue.From(true),
    ["volume"] = JsValue.From(0.75)
});
```

### Exposing Plugin Methods

Register handlers in `IEmbeddedScriptBridge.Methods`. Method names must be simple JavaScript identifiers (≤128 chars) and are validated when the instance is created:

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

## Limits and Timeouts

Enforced by the sandbox broker; exceeding a limit fails the call:

| Resource | Limit |
|---|---|
| IPC control (JSON) message | 4 MiB |
| IPC binary frame (pixels, streamed content) | 64 MiB |
| Stream chunk | 1 MiB |
| Page text / link count | 512 KiB / 2,000 |
| History search results | 100 |
| Bookmark list | 500 |
| Network rules | 100 |
| Page CSS | 64 KiB |
| Content transform input / output | 8 MiB each |
| Protocol response body | 32 MiB |
| PCM audio push | 1 MiB (8–48 kHz, 1–2 ch, s16le / f32le) |
| Toolbar icon | 64 KiB PNG |
| Badge text | 32 chars |
| Omnibox suggestions | 8 (text ≤256, URL ≤8192, description ≤512) |
| RPC call timeout | 30 s default · ~1 s `embed.render` · 750 ms `beforeNavigate` |
| Reserved protocol schemes | `http`, `https`, `file`, `about`, `data`, `javascript`, `mailto`, `retro96` |
| Host-controlled HTTP headers | `Host`, `Content-Length`, `Connection` (`Cookie` requires `browser.cookies`) |

A slow or throwing `BeforeNavigate` handler never blocks navigation: the default outcome is *allow* (an invalid redirect target yields *cancel*).

## Security & Isolation Model

* Each enabled plugin runs in its **own sandboxed worker process** — the Retro96 binary relaunched as a plugin worker — inside a per-plugin Windows **AppContainer** profile and **Job Object** (kill-on-close, single child process, per-process memory cap, CPU capped at 25%).
* All communication crosses a **named-pipe broker** whose ACL contains only that plugin's AppContainer SID. Permissions are demanded on both ends: the worker refuses to send operations the plugin hasn't been granted, and the host re-checks on receipt.
* No direct access to host filesystem paths (the plugin sees only its private data directory, with path-escape checks), no raw network sockets (HTTP is brokered and header-injection is rejected), and no window or GDI handles (frames are composited host-side via Skia).
* Plugin-produced content is sanitized before use: transform HTML has script elements, `on*` attributes, and script-scheme URLs stripped; injected CSS has `url()`, `@import`, `-moz-binding`, and `behavior` removed; custom protocol responses are parsed by the normal, untrusted-content renderer path.
* Permission-gated calls are recorded in the per-plugin activity log; crashes are contained (the worker dies, the browser doesn't) and repeated crashes auto-disable the plugin.
