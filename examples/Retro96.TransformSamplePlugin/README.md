# Retro96 Transform Sample

A small example for the current `content.transform` API. Its manifest declares a scoped HTML transform for `https://example.test/*`.

## Build and package

From the SDK root:

```powershell
.\scripts\pack-plugin.ps1 .\examples\Retro96.TransformSamplePlugin
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
    └── retro96.transform.sample-1.0.0.r96p
```

The example uses `IPluginContentTransform.Register` from the current API. Change `content_transform_scopes` in `plugin.json` when experimenting with other response scopes.
