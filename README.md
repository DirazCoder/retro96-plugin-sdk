# Retro96 Plugin SDK

Retro96 extensions are **C#/.NET class-library plugins** packaged as a custom `.r96p` file. API version 1 is the public contract under `Retro96.Plugins`.

A plugin is not a browser page, JavaScript snippet, or arbitrary script. The plugin entry point implements `IRetro96Plugin` and communicates with the browser through the versioned host API. The SDK is a separate project and is the only compile-time dependency plugin authors need from Retro96.
## Project boundary

The SDK is deliberately separate from the Retro96 browser application. Plugin authors should **not** reference `retro96/Retro96.csproj` and should not copy browser engine source files into a plugin. The SDK contains the public C# contracts, manifest types, permission names, and helper types that define the plugin ABI. The browser implements those contracts behind the existing sandbox broker.

This follows the same general SDK workflow used by mature browser extension systems: developer-facing headers/contracts are compiled together with the extension's own code, while the host implementation remains separate. Retro96's SDK is entirely original; it does not bundle or redistribute Netscape code or NPAPI headers.


## Package format

`.r96p` is a ZIP-compatible package with this shape:

```text
example.r96p
├── plugin.json
└── lib/
    └── ExamplePlugin.dll
```

`plugin.json` is required at the package root:

```json
{
  "id": "example.hello",
  "name": "Hello Plugin",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Example",
  "description": "Adds a command and watches page navigation.",
  "assembly": "lib/ExamplePlugin.dll",
  "entryPoint": "Example.HelloPlugin",
  "permissions": [
    "ui",
    "browser.read",
    "browser.events"
  ]
}
```

Required manifest fields are `id`, `name`, `version`, `apiVersion`, `assembly`, and `entryPoint`. Package paths are validated against traversal and the entry assembly must stay inside the package.

## Minimal C# plugin

```csharp
using Retro96.Plugins;

namespace Example;

public sealed class HelloPlugin : IRetro96Plugin
{
    private IDisposable? _command;

    public void Initialize(IRetro96PluginHost host)
    {
        _command = host.Ui.AddFileMenuItem("Hello from plugin", () =>
        {
            host.Ui.ShowMessage("Hello", host.Browser.CurrentUrl ?? "No page loaded");
        });

        host.Events.PageLoaded += (_, e) =>
            host.Log.Info($"Loaded {e.Url}");
    }

    public void Dispose() => _command?.Dispose();
}
```

Build the plugin as a normal C# class library targeting `.NET 11`. Reference `Retro96.Plugin.SDK.csproj` (or the produced `Retro96.Plugin.SDK.dll`) rather than referencing the Retro96 browser application. The browser and plugins share the public `Retro96.Plugins` contract assembly at runtime.

The sample project is configured so every successful `Build` or `Publish` also copies the plugin DLL to `examples/Retro96.SamplePlugin/dist/lib/Retro96.SamplePlugin.dll`. The `.dll` is the required compiled plugin payload; the `.r96p` package must contain that DLL at the manifest `assembly` path.

The main `Retro96` project still builds the bundled sample plugin after a successful host build. Because the sample plugin references only the SDK, not the browser project, there is no host/plugin circular dependency. The solution also includes the SDK and sample plugin as independent buildable projects.

### SDK bootstrap

This SDK intentionally targets `.NET 11`. From this directory, run:

```powershell
.\build.ps1
```

`build.ps1` downloads the official .NET 11 SDK bootstrap installer when the requested SDK is not present, installs it into `.dotnet\`, restores the SDK project, builds it, and produces:

```text
artifacts\bin\Release\Retro96.Plugin.SDK.dll
artifacts\packages\Retro96.Plugin.SDK.1.0.0.nupkg
```

For a plugin project, reference `Retro96.Plugin.SDK.csproj` while developing, or consume the packed `Retro96.Plugin.SDK` package. Do not reference `retro96\Retro96.csproj` just to obtain plugin API types.

## Loading and lifecycle

The browser only loads API version 1 plugins. The manager installs a package into:

```text
%LOCALAPPDATA%\Retro96\Plugins\<plugin-id>\
```

Persistent plugin state is stored in:

```text
%LOCALAPPDATA%\Retro96\Plugins\plugin-state.json
```

Private plugin data is stored under:

```text
%LOCALAPPDATA%\Retro96\Plugins\<plugin-id>\data\
```

`Initialize(IRetro96PluginHost)` is called once after the sandbox handshake. `Dispose()` is called on disable, reload, removal, worker shutdown, or browser exit.

## Plugin Addons

Open **File → Plugin Addons…**.

The manager provides:

- **Add…** — install a `.r96p` package.
- **Delete** — remove the installed plugin and its private data after confirmation.
- **Enable / Disable** — start or stop a plugin.
- **Details…** — show manifest and runtime information.
- **Permissions…** — grant or revoke requested capabilities.
- **Reload** — restart an enabled plugin worker.
- **Open Folder** — open the installed package directory.
- **Close** — close the manager.

The dialog uses a top header, a resizable center list, a right-side action column, and a bounded details area so long plugin names and permission lists do not compress the title or clip the bottom controls.

New plugins are installed **disabled**. The user must explicitly grant requested permissions and enable the plugin.

## API version 1

All services below are available from `IRetro96PluginHost` and remain in API version 1. Existing version-1 APIs are additive-compatible with this expanded surface.

### `IRetro96PluginHost`

```csharp
PluginManifest Manifest { get; }
PluginPermission GrantedPermissions { get; }
IPluginBrowser Browser { get; }
IPluginUi Ui { get; }
IPluginStorage Storage { get; }
IPluginNetwork Network { get; }
IPluginFileSystem FileSystem { get; }
IPluginClipboard Clipboard { get; }
IPluginEvents Events { get; }
IPluginAudio Audio { get; }
IPluginNotifications Notifications { get; }
IPluginDialogs Dialogs { get; }
IPluginLogger Log { get; }
bool HasPermission(PluginPermission permission);
```

The `IPlugin*` interfaces extend the named API services (`IBrowserService`, `IUiService`, and so on) so existing source continues to use the compact `host.Browser`, `host.Ui` form.

### Browser: `IBrowserService`

Existing browser navigation remains permission-gated. API version 1 additionally provides:

```csharp
float Zoom { get; set; }                         // browser.zoom
(int Width, int Height) ViewportSize { get; }    // browser.read
string? GetCookie(string name);                  // browser.cookies
void SetCookie(string name, string value,
               CookieOptions options);            // browser.cookies
void Find(string text, bool caseSensitive,
          bool wrapAround);                      // browser.find
void FindNext();                                 // browser.find
void FindClear();                                // browser.find
byte[] CaptureViewport();                        // browser.screenshot
```

`CookieOptions` supports `Path`, `Domain`, `Expires`, and `Secure`. Cookie access is scoped through the current page's origin and uses the browser's existing `CookieStore`.

### UI: `IUiService`

```csharp
IDisposable AddFileMenuItem(string text, Action callback);
IDisposable AddToolbarButton(string label, string tooltip, Action onClick);  // ui
IDisposable AddContextMenuItem(
    string label,
    Func<ContextMenuContext, bool> shouldShow,
    Action<ContextMenuContext> onClick);                                   // ui
void SetStatus(string text);                                                // ui
void SetProgress(double? fraction);                                         // ui
void ShowMessage(string title, string message);                             // ui
Task<string?> ShowInputDialog(string title, string prompt,
                              string? defaultValue);                        // ui
IPluginPanel CreatePanel(string title);                                     // ui.panel
```

`ContextMenuContext` contains:

```csharp
string? TargetUrl;
string? TargetText;
bool IsLink;
bool IsImage;
```

`AddToolbarButton` inserts a text button into the plugin toolbar below the browser controls. `SetProgress(null)` removes the plugin's progress indicator. `ShowInputDialog` returns `null` on Cancel.

#### `IPluginPanel`

Panels are host-rendered and do **not** expose raw WinForms handles:

```csharp
public interface IPluginPanel : IDisposable
{
    IPluginWidget AddLabel(string text);
    IPluginWidget AddButton(string label, Action onClick);
    IPluginWidget AddTextBox(string placeholder, Action<string> onChange);
    IPluginWidget AddCheckBox(string label, bool initial, Action<bool> onChange);
    IPluginWidget AddListBox(IEnumerable<string> items, Action<int> onSelect);
    void Clear();
    void Show();
    void Hide();
}
```

The broker translates widget callbacks back to the plugin worker. Plugin code never receives the host `Control` tree.

### Network: `IPluginNetwork`

Permission: `network`.

```csharp
Task<string> GetStringAsync(string url);
Task<byte[]> GetBytesAsync(string url);
Task<string> PostStringAsync(string url, string body, string contentType);
Task<byte[]> PostBytesAsync(string url, byte[] body, string contentType);
Task<string> SendAsync(HttpPluginRequest request);
```

`HttpPluginRequest` contains:

```csharp
string Method;
string Url;
IReadOnlyDictionary<string, string>? Headers;
byte[]? Body;
string? ContentType;
```

The host broker rejects host-controlled headers such as `Host`, `Content-Length`, and `Connection`. `Cookie` requires `browser.cookies` and is never accepted merely because the plugin has `network`.

All requests use the browser's existing `Engine/Network/HttpClient` and cookie/redirect behavior rather than a second network stack.

### Filesystem: `IPluginFileSystem`

Permission: `filesystem`.

```csharp
string DataDirectory { get; }
byte[] ReadAllBytes(string relativePath);
string ReadAllText(string relativePath);
void WriteAllBytes(string relativePath, byte[] content);
void WriteAllText(string relativePath, string content);
bool Exists(string relativePath);
string[] ListFiles(string? subdirectory);
void Delete(string relativePath);
void CreateDirectory(string relativePath);
```

Paths are plugin-relative and broker-resolved beneath the private `data` directory. `..` traversal and rooted paths are rejected.

### Storage: `IPluginStorage`

Permission: `storage`.

Existing string key/value operations remain. API version 1 adds:

```csharp
string[] ListKeys(string? prefix);
T? GetObject<T>(string key);
void SetObject<T>(string key, T value);
long GetUsedBytes();
```

Objects are serialized with `System.Text.Json` into the plugin's existing storage file.

### Events: `IPluginEvents`

```csharp
event EventHandler<PluginNavigationEventArgs> Navigated;
event EventHandler<PluginPageEventArgs> PageLoaded;
event EventHandler HostShuttingDown;                   // browser.events
    
event EventHandler<FocusEventArgs> WindowFocusChanged; // browser.events
IDisposable CreateTimer(TimeSpan interval, Action callback); // no permission
```

`CreateTimer` runs inside the plugin worker, so the timer does not directly enter the WinForms UI thread. Dispose the returned timer lease when the plugin stops using it.

`HostShuttingDown` is raised before the host begins tearing down plugin workers. Plugin handlers should flush short-lived state and return quickly.

### Clipboard: `IPluginClipboard`

Permission: `clipboard`.

```csharp
string? GetText();
void SetText(string text);
event EventHandler ClipboardChanged;
byte[]? GetImage();
void SetImage(byte[] pngBytes);
```

Images cross the sandbox as PNG bytes. Clipboard monitoring is host-polled and the event is delivered only to plugins that hold the clipboard permission.

### Audio: `IPluginAudio`

Permission: `audio.playback`.

```csharp
Task PlayFileAsync(string path);
void Stop();
bool IsPlaying { get; }
float Volume { get; set; }
bool Loop { get; set; }
event EventHandler PlaybackComplete;
```

The `path` argument is always interpreted relative to the plugin's private sandbox data directory. The plugin never receives a real host filesystem path. Retro96 uses the same Windows MCI/winmm playback mechanism as its built-in MIDI/WAV player.

### Notifications: `IPluginNotifications`

Permission: `notifications`.

```csharp
void Show(string title, string body);
void Show(string title, string body, Action onClick);
```

The host currently surfaces these through the Windows shell notification/balloon mechanism; the callback is returned through the sandbox IPC event channel. A click callback is delivered back to the plugin worker through the IPC event channel.

### File pickers: `IPluginDialogs`

Permission: `dialogs`.

```csharp
Task<string?> OpenFilePickerAsync(string title, string filter);
Task<bool> SaveFilePickerAsync(string sandboxRelativePath,
                               string suggestedFilename,
                               string filter);
```

`OpenFilePickerAsync` copies the chosen host file **into the plugin's private `data/imports` directory** and returns only the sandbox-relative path. `SaveFilePickerAsync` copies a private sandbox file out to a user-selected destination. The plugin never receives the destination or source host path.

### Logging: `IPluginLogger`

Logging does not require an extra permission:

```csharp
void Info(string message);
void Warn(string message);
void Error(string message, Exception? exception = null);
```

Messages are routed through Retro96's existing debug log facility.

## Permissions

All permission checks happen twice: once in the plugin worker API proxy and again at the trusted host broker.

| Manifest permission | Capability |
|---|---|
| `browser.read` | Read current URL/title and viewport size |
| `browser.navigate` | Navigate, reload, back, forward, scroll |
| `browser.windows` | Open another Retro96 window |
| `browser.events` | Receive navigation, page-loaded, shutdown, and focus events |
| `browser.zoom` | Get/set page zoom |
| `browser.cookies` | Read/write cookies for the current origin and authorize network Cookie headers |
| `browser.find` | Find/next/clear in-page search |
| `browser.screenshot` | Capture the current viewport as PNG |
| `ui` | File-menu items, toolbar buttons, context menu items, messages, input dialogs, status/progress |
| `ui.panel` | Create host-rendered plugin panels |
| `storage` | Persistent per-plugin key/value/object storage |
| `network` | Brokered HTTP requests |
| `filesystem` | Files inside the plugin private data directory |
| `clipboard` | Clipboard text/image read/write and change events |
| `audio.playback` | Play files from the plugin private sandbox |
| `notifications` | Host OS notification service |
| `dialogs` | Sandbox-safe open/save file pickers |

Permissions are additive. A plugin declares only what it needs. Granting `network` does not automatically grant cookies, filesystem, UI, or browser navigation.

## Sandbox architecture

Enabled plugins do **not** execute in the main browser process.

Retro96 starts a dedicated worker process for each enabled plugin and gives that worker:

- a Windows **AppContainer** identity;
- a **kill-on-close Job Object** with process/memory limits;
- child-process mitigation;
- a private runtime copy containing the plugin package;
- a per-plugin named-pipe connection to the trusted browser host.

The worker exposes the public C# API locally as RPC proxy objects. Every privileged operation crosses the pipe and is checked against the plugin's **currently granted permission mask** by the trusted host broker.

The worker does not receive the host browser `Form1`, renderer, DOM, network client, cookie store, or raw host filesystem paths.

The private plugin data directory is the only filesystem namespace exposed to the plugin API. Picker operations copy files across that boundary instead of exposing source/destination paths.

If a worker crashes or disconnects, Retro96 marks the plugin as **Error** and leaves the main browser running. Reload/disable/removal tears down the worker and its Job Object.

## Safety and trust model

The sandbox reduces the direct reach of extension code, but `.r96p` files are still compiled C# and should be treated as third-party executable software. Only install packages you trust.

The permission broker remains a deliberate security boundary even though the worker is already isolated. New privileged capabilities should always add a manifest permission and a host-side permission check.

## Versioning

`apiVersion` is the compatibility boundary. The current public API is version **1**.

This feature expansion is intentionally additive: the `.r96p` package format, `plugin.json` shape, manager workflow, sandbox worker, named-pipe broker, AppContainer launch, and Job Object isolation remain in place.

## Built-in browser features (not plugins)

The following are host features and remain available without installing an extension:

- **Bookmarks** — stored at `%LOCALAPPDATA%\Retro96\bookmarks.json`; the Bookmarks menu shows the newest 30 entries and **Manage Bookmarks...** shows the full flat list.
- **History** — stored at `%LOCALAPPDATA%\Retro96\history.json`; visits are de-duplicated by URL, capped at 500 entries, and exposed through the History menu and manager dialog.
- **Downloads** — binary/attachment responses are intercepted by the browser and offered through Save As; **View → Downloads** (or **Ctrl+J**) shows session downloads and their status/progress.
- **MIDI playback** — direct `.mid`/`.midi` navigation and legacy `<embed src="...mid">` / `<bgsound src="...mid">` references use the Windows MCI/winmm playback path. Direct navigation exposes the browser MIDI controls; `<embed>` gets a small inline control strip at the embed position; `bgsound` is invisible and is treated as page audio that follows its loop attribute.

These features do not consume plugin permissions and do not execute extension code.
