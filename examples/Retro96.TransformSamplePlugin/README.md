# Retro96 Transform Sample

This is a small C# example for the `content.transform` API. Its manifest scopes transformations to `https://example.test/*` HTML responses.

The host only delivers responses that match both the declared URL and MIME scopes. Returned HTML is sanitized by the host: `<script>` elements, `on*` event attributes, and `javascript:` URL attributes are removed before the normal page parser runs.

Build with:

```powershell
dotnet build examples/Retro96.TransformSamplePlugin/Retro96.TransformSamplePlugin.csproj -c Release
```

Package with `pack-plugin.ps1` using `plugin.json` from this directory.
