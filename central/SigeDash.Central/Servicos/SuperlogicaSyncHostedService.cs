using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Modelos;

namespace SigeDash.Central.Servicos;

/// <summary>
/// Polling diário do Superlógica → estado da assinatura na Central (kill-switch automático).
/// Para cada cliente COM CNPJ e que NÃO esteja em 'trial' (trial é manual), consulta o Superlógica e
/// ajusta o estado. FAIL-SAFE: consulta que falha/não conclui NÃO altera o estado (nunca bloqueia por
/// erro de API). No-op se o Superlógica não estiver configurado.
/// </summary>
public sealed class SuperlogicaSyncHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopes;
    private readonly SuperlogicaClient _sl;
    private readonly IConfiguration _cfg;
    private readonly ILogger<SuperlogicaSyncHostedService> _log;

    public SuperlogicaSyncHostedService(IServiceScopeFactory scopes, SuperlogicaClient sl,
        IConfiguration cfg, ILogger<SuperlogicaSyncHostedService> log)
    {
        _scopes = scopes; _sl = sl; _cfg = cfg; _log = log;
    }

    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        if (!_sl.Configurado)
        {
            _log.LogInformation("Sync Superlógica desativado (Superlogica:AppToken/AccessToken não configurados).");
            return;
        }
        var hora = Math.Clamp(_cfg.GetValue("Superlogica:HoraSyncUtc", 6), 0, 23);

        // pequeno atraso no boot; roda uma vez e depois todo dia na hora configurada (UTC)
        try { await Task.Delay(TimeSpan.FromSeconds(30), ct); } catch { return; }

        while (!ct.IsCancellationRequested)
        {
            try { await SincronizarAsync(ct); }
            catch (Exception ex) { _log.LogWarning("Sync Superlógica: erro no ciclo: {m}", ex.Message); }

            var agora = DateTime.UtcNow;
            var prox = agora.Date.AddHours(hora);
            if (prox <= agora) prox = prox.AddDays(1);
            try { await Task.Delay(prox - agora, ct); } catch { break; }
        }
    }

    private async Task SincronizarAsync(CancellationToken ct)
    {
        using var scope = _scopes.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<CentralDbContext>();

        // DRY-RUN (padrão): só loga o que MUDARIA, sem aplicar — para validar o mapeamento/parsing
        // com dados reais antes de deixar a automação alterar estados de verdade.
        var dryRun = _cfg.GetValue("Superlogica:DryRun", true);

        // Só clientes com CNPJ e fora do trial (trial é manual e intocável pela automação).
        var clientes = await db.Clientes
            .Where(c => c.Cnpj != null && c.Cnpj != "" && c.Estado != EstadoAssinatura.Trial)
            .ToListAsync(ct);

        var mudou = 0;
        foreach (var c in clientes)
        {
            if (ct.IsCancellationRequested) break;

            var status = await _sl.ConsultarPorCnpjAsync(c.Cnpj!, ct);
            if (status is null) continue;   // FAIL-SAFE: erro/sem resposta não altera o estado

            var novo = MapearEstado(status);
            if (novo == c.Estado) { if (!dryRun) c.SincronizadoSuperlogicaEm = DateTime.UtcNow; continue; }

            if (dryRun)
            {
                _log.LogInformation("Sync Superlógica [DRY-RUN] {nome}: {de} → {para} (item={item}, emDia={emDia}) — NÃO aplicado.",
                    c.Nome, c.Estado, novo, status.TemItemSigedash, status.EmDia);
                continue;
            }

            var anterior = c.Estado;
            c.Estado = novo;
            c.MotivoBloqueio = EstadoAssinatura.Bloqueia(novo) ? MotivoDe(status) : null;
            c.EstadoAtualizadoEm = DateTime.UtcNow;
            c.EstadoPor = "superlogica";
            c.SincronizadoSuperlogicaEm = DateTime.UtcNow;
            db.LogsAuditoria.Add(new LogAuditoria
            {
                Usuario = "superlogica",
                Acao = "estado_assinatura",
                ClienteId = c.Id,
                Detalhe = $"{c.Nome}: {anterior} → {novo} (Superlógica)"
            });
            mudou++;
        }

        if (!dryRun) await db.SaveChangesAsync(ct);
        _log.LogInformation("Sync Superlógica{dry}: {n} cliente(s) {verbo}.",
            dryRun ? " [DRY-RUN]" : "", dryRun ? clientes.Count : mudou, dryRun ? "avaliados" : "ajustados");
    }

    // Regra definida pelo usuário: sem o item SigeDash OU contrato inexistente/cancelado → cancelado;
    // item ativo mas inadimplente → suspenso; item ativo e em dia → ativo.
    private static string MapearEstado(StatusSuperlogica s)
    {
        if (!s.Encontrado || !s.TemItemSigedash) return EstadoAssinatura.Cancelado;
        if (!s.EmDia) return EstadoAssinatura.Suspenso;
        return EstadoAssinatura.Ativo;
    }

    private static string MotivoDe(StatusSuperlogica s) =>
        !s.Encontrado || !s.TemItemSigedash
            ? "Assinatura cancelada. Contate a SistemasBr."
            : "Pagamento em atraso. Regularize para reativar.";
}
