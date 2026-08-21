using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;

namespace SigeDash.Central.Servicos;

/// <summary>
/// Retenção (LGPD / B-05): expurga HeartbeatHistorico mais antigo que Retencao:HistoricoDias (padrão 90).
/// O estado atual (Heartbeat) e a saúde por indicador não são afetados. Roda no boot e a cada 24h.
/// </summary>
public class RetencaoHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopes;
    private readonly IConfiguration _cfg;
    private readonly ILogger<RetencaoHostedService> _log;

    public RetencaoHostedService(IServiceScopeFactory scopes, IConfiguration cfg, ILogger<RetencaoHostedService> log)
    { _scopes = scopes; _cfg = cfg; _log = log; }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        try { await Task.Delay(TimeSpan.FromMinutes(2), ct); } catch { return; }   // deixa o boot/migração terminar

        while (!ct.IsCancellationRequested)
        {
            try
            {
                var dias = Math.Max(1, _cfg.GetValue("Retencao:HistoricoDias", 90));
                var corte = DateTime.UtcNow.AddDays(-dias);
                using var scope = _scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<CentralDbContext>();
                var apagados = await db.HeartbeatHistorico.Where(h => h.Ts < corte).ExecuteDeleteAsync(ct);
                if (apagados > 0) _log.LogInformation("Retenção: {n} heartbeats antigos (>{d}d) expurgados.", apagados, dias);
            }
            catch (Exception ex) { _log.LogWarning("Retenção falhou: {msg}", ex.Message); }

            try { await Task.Delay(TimeSpan.FromHours(24), ct); } catch { break; }
        }
    }
}
