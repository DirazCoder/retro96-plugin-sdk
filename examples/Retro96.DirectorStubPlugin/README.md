# Retro96 Director Stub Plugin

A wiring-only embedded-content example for `application/x-director` using the current 1.0.0 embedded API.

It exercises:

- `EmbeddedContentRegistration`
- bounded `IPluginByteStream` reads
- host-composited BGRA frame rendering
- embedded input events
- the typed asynchronous `JsValue` bridge

It does not implement a Director VM.

## Build and package

From the SDK root:

```powershell
.\scripts\pack-plugin.ps1 .\examples\Retro96.DirectorStubPlugin
```

From this plugin directory:

```powershell
..\..\scripts\pack-plugin.ps1
```

Output:

```text
dist/
├── build/
├── obj/
├── lib/
└── packages/
    └── retro96.director.stub-1.0.0.r96p
```

The sample uses the new typed JavaScript bridge (`JsValue`) and converts its byte count to `double`, matching the 1.0.0 API surface.
