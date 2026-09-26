# Retro96 Sample Plugin

This project is a real C# plugin built against the standalone `Retro96.Plugin.SDK` project.

It does not reference the browser host project for API contracts. The SDK is the only Retro96 compile-time dependency needed to write a plugin.

Build it with:

```powershell
dotnet build examples/Retro96.SamplePlugin/Retro96.SamplePlugin.csproj -c Release
```

The compiled plugin DLL is copied to:

```text
examples/Retro96.SamplePlugin/dist/lib/Retro96.SamplePlugin.dll
```

Use `../../Retro96.Plugin.SDK/pack-plugin.ps1` to build and package it as `.r96p`.
