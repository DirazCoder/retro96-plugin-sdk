# SDK scripts

The SDK workflow is intentionally small:

```powershell
.\scripts\build.ps1
```

Builds and packs the SDK only.

```powershell
.\scripts\new-plugin.ps1 MyPlugin
```

Creates a clean plugin project with `1.0.0` defaults.

```powershell
.\scripts\pack-plugin.ps1 .\examples\MyPlugin
```

Finds the plugin project and manifest automatically, cleans its `dist/`, builds it, stages runtime dependencies, and creates the `.r96p` package.

`resolve-dotnet11.ps1` and `bootstrap-dotnet11.ps1` are helper scripts used when a suitable `dotnet` executable is not already available.
