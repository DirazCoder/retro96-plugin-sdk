using Retro96.Plugins;

namespace Retro96.DirectorStubPlugin;

/// <summary>
/// Wiring-only embedded renderer. It exercises MIME registration, push-stream
/// backpressure, host-composited pixel frames, input delivery and the async
/// page/plugin JS bridge without implementing a Director VM.
/// </summary>
public sealed class DirectorStubPlugin : IRetro96Plugin
{
    private IDisposable? _registration;
    private IRetro96PluginHost? _host;

    public void Initialize(IRetro96PluginHost host)
    {
        _host = host;
        _registration = host.Embeds.Register(new EmbeddedContentRegistration(
            ["application/x-director"],
            static (context, stream, embedHost, scripts) => new DirectorStubInstance(context, stream, embedHost, scripts)));
        host.Log.Info("Director stub embedded-content renderer registered.");
    }

    public void Dispose()
    {
        _registration?.Dispose();
        _registration = null;
        _host = null;
    }

    private sealed class DirectorStubInstance : IEmbeddedContentInstance
    {
        private static readonly byte[][] Glyphs = BuildGlyphs();
        private readonly EmbeddedContentContext _context;
        private readonly IPluginByteStream _stream;
        private readonly IEmbeddedContentHost _host;
        private readonly IEmbeddedScriptBridge _scripts;
        private readonly object _sync = new();
        private long _bytesReceived;
        private bool _ended;

        public DirectorStubInstance(EmbeddedContentContext context, IPluginByteStream stream,
                                    IEmbeddedContentHost host, IEmbeddedScriptBridge scripts)
        {
            _context = context;
            _stream = stream;
            _host = host;
            _scripts = scripts;
            _scripts.Methods["getByteCount"] = _ => Task.FromResult(JsValue.From(Bytes));
            _scripts.Methods["getMimeType"] = _ => Task.FromResult(JsValue.From(_context.MimeType));
            _stream.ChunkReceived += OnChunk;
            _ = _stream.RequestMoreAsync(256 * 1024);
        }

        private long Bytes { get { lock (_sync) return _bytesReceived; } }

        private void OnChunk(object? sender, EmbeddedStreamChunkEventArgs e)
        {
            bool end;
            lock (_sync)
            {
                _bytesReceived = checked(_bytesReceived + e.Data.LongLength);
                end = e.EndOfStream;
                if (end) _ended = true;
            }
            if (e.Error is { Length: > 0 })
                _ = _host.SetStatusAsync($"Director stub stream error: {e.Error}");
            else if (end)
            {
                _ = _host.SetStatusAsync($"Director stub received {Bytes:n0} bytes");
                _ = NotifyPageAsync();
            }
            else
            {
                // Pull the next bounded window only after the current chunk
                // has been delivered, keeping host buffering finite.
                _ = _stream.RequestMoreAsync(256 * 1024);
            }
        }

        private async Task NotifyPageAsync()
        {
            try
            {
                await _scripts.CallPageFunction("retro96DirectorStreamReady",
                    [JsValue.From(Bytes), JsValue.From(_context.MimeType)]).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                await _host.SetStatusAsync($"Director stub page callback failed: {ex.Message}").ConfigureAwait(false);
            }
        }

        public Task<EmbeddedFrameBuffer> RenderAsync(EmbeddedRenderRequest request, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            int width = request.Width;
            int height = request.Height;
            int stride = request.Stride;
            if (stride < checked(width * 4)) throw new ArgumentOutOfRangeException(nameof(request));
            byte[] pixels = new byte[checked(stride * height)];
            FillGray(pixels, width, height, stride, 192);

            string line1 = _context.MimeType;
            string line2 = $"bytes: {Bytes:n0}";
            int scale = Math.Clamp(Math.Min(width / Math.Max(1, TextWidth(line1)), height / 20), 1, 3);
            int y = Math.Max(2, (height - (7 * scale * 2 + 4 * scale)) / 2);
            DrawText(pixels, width, height, stride, line1, scale, y, 32, 32, 32);
            DrawText(pixels, width, height, stride, line2, scale, y + 9 * scale, 32, 32, 32);
            return Task.FromResult(new EmbeddedFrameBuffer(width, height, stride, pixels));
        }

        public Task HandleInputAsync(EmbeddedInputEvent inputEvent, CancellationToken cancellationToken = default)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (inputEvent.Kind == EmbeddedInputEventKind.MouseDown)
                _ = _host.SetStatusAsync("Director stub received mouse input");
            return Task.CompletedTask;
        }

        public void Dispose()
        {
            _stream.ChunkReceived -= OnChunk;
            _stream.Dispose();
        }

        private static void FillGray(byte[] pixels, int width, int height, int stride, byte gray)
        {
            for (int y = 0; y < height; y++)
            {
                int row = y * stride;
                for (int x = 0; x < width; x++)
                {
                    int i = row + x * 4;
                    pixels[i + 0] = gray;
                    pixels[i + 1] = gray;
                    pixels[i + 2] = gray;
                    pixels[i + 3] = 255;
                }
            }
        }

        private static int TextWidth(string text) => Math.Max(1, text.Length * 6);

        private static void DrawText(byte[] pixels, int width, int height, int stride,
                                     string text, int scale, int y, byte r, byte g, byte b)
        {
            int totalWidth = text.Length * 6 * scale;
            int startX = Math.Max(0, (width - totalWidth) / 2);
            int x = startX;
            foreach (char ch in text)
            {
                int glyph = ch is >= ' ' and <= '~' ? ch - ' ' : '?' - ' ';
                var rows = Glyphs[glyph];
                for (int gy = 0; gy < 7; gy++)
                {
                    byte bits = rows[gy];
                    for (int gx = 0; gx < 5; gx++)
                    {
                        if ((bits & (1 << (4 - gx))) == 0) continue;
                        for (int dy = 0; dy < scale; dy++)
                        for (int dx = 0; dx < scale; dx++)
                        {
                            int px = x + gx * scale + dx;
                            int py = y + gy * scale + dy;
                            if ((uint)px >= (uint)width || (uint)py >= (uint)height) continue;
                            int i = py * stride + px * 4;
                            pixels[i + 0] = b;
                            pixels[i + 1] = g;
                            pixels[i + 2] = r;
                            pixels[i + 3] = 255;
                        }
                    }
                }
                x += 6 * scale;
            }
        }

        private static byte[][] BuildGlyphs()
        {
            var result = new byte[95][];
            for (int i = 0; i < result.Length; i++) result[i] = new byte[7];
            // Minimal readable set; unlisted punctuation/letters fall back to '?'.
            void Put(char c, params string[] rows)
            {
                var g = new byte[7];
                for (int i = 0; i < Math.Min(7, rows.Length); i++)
                    for (int x = 0; x < Math.Min(5, rows[i].Length); x++)
                        if (rows[i][x] != ' ') g[i] |= (byte)(1 << (4 - x));
                result[c - ' '] = g;
            }
            Put('?', "11110","00001","00010","00100","00100","00000","00100");
            Put(':', "00000","00100","00100","00000","00100","00100","00000");
            Put('-', "00000","00000","00000","11111","00000","00000","00000");
            Put('.', "00000","00000","00000","00000","00000","00110","00110");
            Put('/', "00001","00010","00100","01000","10000","00000","00000");
            string[][] digits =
            {
                ["01110","10001","10011","10101","11001","10001","01110"],
                ["00100","01100","00100","00100","00100","00100","01110"],
                ["01110","10001","00001","00010","00100","01000","11111"],
                ["11110","00001","00001","01110","00001","00001","11110"],
                ["00010","00110","01010","10010","11111","00010","00010"],
                ["11111","10000","10000","11110","00001","00001","11110"],
                ["00110","01000","10000","11110","10001","10001","01110"],
                ["11111","00001","00010","00100","01000","01000","01000"],
                ["01110","10001","10001","01110","10001","10001","01110"],
                ["01110","10001","10001","01111","00001","00010","01100"]
            };
            for (int i = 0; i < digits.Length; i++) Put((char)('0' + i), digits[i]);
            string[][] letters =
            {
                ["01110","10001","10001","11111","10001","10001","10001"],
                ["11110","10001","10001","11110","10001","10001","11110"],
                ["01111","10000","10000","10000","10000","10000","01111"],
                ["11110","10001","10001","10001","10001","10001","11110"],
                ["11111","10000","10000","11110","10000","10000","11111"],
                ["11111","10000","10000","11110","10000","10000","10000"],
                ["01111","10000","10000","10111","10001","10001","01111"],
                ["10001","10001","10001","11111","10001","10001","10001"],
                ["11111","00100","00100","00100","00100","00100","11111"],
                ["00111","00010","00010","00010","10010","10010","01100"],
                ["10001","10010","10100","11000","10100","10010","10001"],
                ["10000","10000","10000","10000","10000","10000","11111"],
                ["10001","11011","10101","10101","10001","10001","10001"],
                ["10001","11001","10101","10011","10001","10001","10001"],
                ["01110","10001","10001","10001","10001","10001","01110"],
                ["11110","10001","10001","11110","10000","10000","10000"],
                ["01110","10001","10001","10001","10101","10010","01101"],
                ["11110","10001","10001","11110","10100","10010","10001"],
                ["01111","10000","10000","01110","00001","00001","11110"],
                ["11111","00100","00100","00100","00100","00100","00100"],
                ["10001","10001","10001","10001","10001","10001","01110"],
                ["10001","10001","10001","10001","10001","01010","00100"],
                ["10001","10001","10001","10101","10101","11011","10001"],
                ["10001","10001","01010","00100","01010","10001","10001"],
                ["10001","10001","01010","00100","00100","00100","00100"],
                ["11111","00001","00010","00100","01000","10000","11111"]
            };
            for (int i = 0; i < letters.Length; i++) Put((char)('A' + i), letters[i]);
            for (int i = 0; i < 26; i++) result[('a' + i) - ' '] = result[('A' + i) - ' '];
            return result;
        }
    }
}
