# Retro96 Sample Plugin

A small plugin that adds a File menu command and logs page-load events using the current 1.0.0 API.

## Build and package

From the SDK root:

```powershell
.\scripts\pack-plugin.ps1 .\examples\Retro96.SamplePlugin
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
    └── retro96.sample-1.0.0.r96p
```

The final package contains `plugin.json` plus runtime files under `lib/`. The shared SDK contract is not packaged.
