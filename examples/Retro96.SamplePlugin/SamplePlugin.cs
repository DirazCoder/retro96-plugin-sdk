using Retro96.Plugins;

namespace Retro96.SamplePlugin;

public sealed class SamplePlugin : IRetro96Plugin
{
    private IDisposable? _command;
    private IRetro96PluginHost? _host;

    public void Initialize(IRetro96PluginHost host)
    {
        _host = host;
        _command = host.Ui.AddFileMenuItem("Sample Plugin: Show URL", () =>
        {
            host.Ui.ShowMessage("Retro96 Sample Plugin",
                host.Browser.CurrentUrl ?? "No page is open.");
        });

        host.Events.PageLoaded += OnPageLoaded;
        host.Log.Info("Sample plugin initialized.");
    }

    private void OnPageLoaded(object? sender, PluginPageEventArgs e) =>
        _host?.Log.Info($"Retro96 loaded {e.Url}");

    public void Dispose()
    {
        _command?.Dispose();
        _command = null;
        _host = null;
    }
}
