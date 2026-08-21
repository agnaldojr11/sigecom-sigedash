using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;

namespace SigeDash.Api.Servicos;

/// <summary>
/// Retenção (LGPD / B-05): mantém apenas o snapshot MAIS RECENTE por (cliente, empresa, indicador)
/// e expurga os antigos. O /dash só usa o último por handle, então nada visível muda — mas o
/// histórico com PII financeira deixa de acumular indefinidamente. Roda no boot e a cada 24h.
/// </summary>
public class RetencaoSnapshotsHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopes;
    private readonly ILogger<RetencaoSnapshotsHostedService> _log;

    // Apaga tudo que não é o mais recente de cada (ClienteId, CodigoEmpresa, IndicadorHandle).
    private const string SqlExpurgo = @"
DELETE FROM ""Snapshots"" s
USING (
  SELECT ""Id"", ROW_NUMBER() OVER (
    PARTITION BY ""ClienteId"",""CodigoEmpresa"",""IndicadorHandle"" ORDER BY ""GeradoEm"" DESC
  ) AS rn
  FROM ""Snapshots""
) t
WHERE s.""Id"" = t.""Id"" AND t.rn > 1;";

    public RetencaoSnapshotsHostedService(IServiceScopeFactory scopes, ILogger<RetencaoSnapshotsHostedService> log)
    { _scopes = scopes; _log = log; }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        try { await Task.Delay(TimeSpan.FromMinutes(2), ct); } catch { return; }   // deixa o boot/migração terminar

        while (!ct.IsCancellationRequested)
        {
            try
            {
                using var scope = _scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
                var apagados = await db.Database.ExecuteSqlRawAsync(SqlExpurgo, ct);
                if (apagados > 0) _log.LogInformation("Retenção: {n} snapshots antigos expurgados (mantido o último por indicador).", apagados);
            }
            catch (Exception ex) { _log.LogWarning("Retenção de snapshots falhou: {msg}", ex.Message); }

            try { await Task.Delay(TimeSpan.FromHours(24), ct); } catch { break; }
        }
    }
}
