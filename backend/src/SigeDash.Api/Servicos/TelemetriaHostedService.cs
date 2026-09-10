using System.Net.Http.Json;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;

namespace SigeDash.Api.Servicos;

/// <summary>
/// Phone-home: envia um heartbeat operacional ao SigeDash Central a cada N minutos.
/// Só métrica/status — nenhum dado de venda ou PII. No-op se Central:Url/ChaveTelemetria vazios.
/// </summary>
public class TelemetriaHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopes;
    private readonly IHttpClientFactory _http;
    private readonly IConfiguration _cfg;
    private readonly ILogger<TelemetriaHostedService> _log;
    private readonly EstadoAssinaturaService _estado;
    private static readonly DateTime _iniciadoEm = DateTime.UtcNow;

    public TelemetriaHostedService(IServiceScopeFactory scopes, IHttpClientFactory http,
        IConfiguration cfg, ILogger<TelemetriaHostedService> log, EstadoAssinaturaService estado)
    {
        _scopes = scopes; _http = http; _cfg = cfg; _log = log; _estado = estado;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        var url   = _cfg["Central:Url"];
        var chave = _cfg["Central:ChaveTelemetria"];
        if (string.IsNullOrWhiteSpace(url) || string.IsNullOrWhiteSpace(chave))
        {
            _log.LogInformation("Telemetria desativada (Central:Url/ChaveTelemetria não configurados).");
            return;
        }
        var intervalo = TimeSpan.FromMinutes(Math.Max(1, _cfg.GetValue("Central:IntervaloMin", 3)));
        var endpoint = url!.TrimEnd('/') + "/telemetria/heartbeat";

        // Pequeno atraso inicial: deixa o backend/DB estabilizarem no boot.
        try { await Task.Delay(TimeSpan.FromSeconds(20), ct); } catch { return; }

        while (!ct.IsCancellationRequested)
        {
            try { await EnviarAsync(endpoint, chave!, ct); }
            catch (Exception ex) { _log.LogWarning("Falha ao enviar heartbeat: {msg}", ex.Message); }

            try { await Task.Delay(intervalo, ct); } catch { break; }
        }
    }

    private async Task EnviarAsync(string endpoint, string chave, CancellationToken ct)
    {
        using var scope = _scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        var statusPg = "ok";
        int usuariosAtivos = 0, limite = 0;
        var indicadores = new List<object>();

        try
        {
            var cliente = await db.Clientes.OrderBy(c => c.Id).FirstOrDefaultAsync(ct);
            limite = cliente?.LimiteDispositivos ?? 0;
            usuariosAtivos = await db.UsuariosApp.CountAsync(u => u.Ativo, ct);

            // Saúde dos indicadores = último snapshot por handle (Fase 1: sucesso + quando).
            var ultimos = await db.Snapshots
                .GroupBy(s => s.IndicadorHandle)
                .Select(g => new { Handle = g.Key, UltimoSucesso = g.Max(s => s.GeradoEm) })
                .ToListAsync(ct);
            foreach (var i in ultimos)
                indicadores.Add(new { handle = i.Handle, status = "ok", ultimoSucesso = i.UltimoSucesso, ultimoErro = (DateTime?)null, mensagem = (string?)null });
        }
        catch (Exception ex)
        {
            statusPg = "erro";
            _log.LogWarning("Telemetria: erro ao ler banco: {msg}", ex.Message);
        }

        var payload = new
        {
            versao            = VersaoInstalada(),
            uptimeSeg         = (long)(DateTime.UtcNow - _iniciadoEm).TotalSeconds,
            usuariosAtivos,
            limiteDispositivos = limite,
            os                = RuntimeInformation.OSDescription,
            statusBackend     = "ok",
            statusPg,
            indicadores
        };

        var http = _http.CreateClient("central");
        http.Timeout = TimeSpan.FromSeconds(20);
        var req = new HttpRequestMessage(HttpMethod.Post, endpoint) { Content = JsonContent.Create(payload) };
        req.Headers.Add("X-Telemetria-Key", chave);
        using var resp = await http.SendAsync(req, ct);
        if (!resp.IsSuccessStatusCode)
        {
            _log.LogWarning("Heartbeat recusado pelo Central: HTTP {code}", (int)resp.StatusCode);
            return; // perda de contato/erro NÃO altera o estado local (fail-open)
        }

        // Aplica o estado de assinatura vindo na resposta (kill-switch por PULL).
        try
        {
            var doc = await resp.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: ct);
            if (doc.ValueKind == JsonValueKind.Object && doc.TryGetProperty("assinatura", out var ass))
            {
                var bloqueado = ass.TryGetProperty("bloqueado", out var b) && b.ValueKind == JsonValueKind.True;
                string? msg = ass.TryGetProperty("mensagem", out var m) && m.ValueKind == JsonValueKind.String ? m.GetString() : null;
                _estado.Atualizar(bloqueado, msg);
            }
        }
        catch (Exception ex) { _log.LogWarning("Telemetria: falha ao ler resposta do heartbeat: {m}", ex.Message); }
    }

    private static string VersaoInstalada()
    {
        try
        {
            var caminho = Path.Combine(AppContext.BaseDirectory, "version.txt");
            if (File.Exists(caminho))
            {
                var v = File.ReadAllText(caminho).Trim();
                if (!string.IsNullOrWhiteSpace(v)) return v;
            }
        }
        catch { /* ignora */ }
        return "0.0.0";
    }
}
