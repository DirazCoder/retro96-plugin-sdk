# Retro96 examples

These are standalone example plugin projects. They are intentionally **not included in `Retro96.Plugin.SDK.sln`** and are never built by `scripts/build.ps1`.

Build and package one example explicitly:

```powershell
.\scripts\pack-plugin.ps1 .\examples\Retro96.SamplePlugin
```

Every plugin keeps generated files inside its own folder:

```text
dist/
├── build/
├── obj/
├── lib/
└── packages/
```

All three examples reference the root `Retro96.Plugin.SDK.csproj` directly so they compile against the current 1.0.0 `Retro96.dll` contract.
