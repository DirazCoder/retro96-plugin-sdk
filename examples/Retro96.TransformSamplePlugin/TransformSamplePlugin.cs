using Retro96.Plugins;

namespace Retro96.TransformSamplePlugin;

public sealed class TransformSamplePlugin : IRetro96Plugin
{
    private IDisposable? _registration;

    public void Initialize(IRetro96PluginHost host)
    {
        _registration = host.ContentTransform.Register(
            "text/html",
            (request, _) => Task.FromResult(
                "<html><body><p>Transformed by Retro96.</p><div>" +
                System.Net.WebUtility.HtmlEncode(request.Url) +
                "</div></body></html>"));
    }

    public void Dispose()
    {
        _registration?.Dispose();
        _registration = null;
    }
}
