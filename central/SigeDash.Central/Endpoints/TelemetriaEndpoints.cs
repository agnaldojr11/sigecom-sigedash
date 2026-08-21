using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Modelos;

namespace SigeDash.Central.Endpoints;

/// <summary>
/// Recebe o que a frota EMPURRA (phone-home). Autenticado por X-Telemetria-Key (chave por cliente).
/// Nenhum dado sensível/PII — só métrica operacional e status.
/// </summary>
public static class TelemetriaEndpoints
{
    public static void MapTelemetria(this IEndpointRouteBuilder app)
    {
        app.MapPost("/telemetria/heartbeat", async (
            HeartbeatDto dto, HttpContext ctx, CentralDbContext db) =>
        {
            var chave = ctx.Request.Headers["X-Telemetria-Key"].ToString();
            if (string.IsNullOrWhiteSpace(chave)) return Results.Unauthorized();

            var cliente = await db.Clientes
                .Include(c => c.Heartbeat)
                .FirstOrDefaultAsync(c => c.ChaveTelemetria == chave && c.Ativo);
            if (cliente is null) return Results.Unauthorized();

            var agora = DateTime.UtcNow;
            var ip = ctx.Connection.RemoteIpAddress?.ToString();

            // Upsert do estado atual
            var hb = cliente.Heartbeat ?? new Heartbeat { ClienteId = cliente.Id };
            hb.RecebidoEm        = agora;
            hb.Versao            = Trunc(dto.Versao, 20);
            hb.UptimeSeg         = Math.Clamp(dto.UptimeSeg, 0, long.MaxValue);
            hb.UsuariosAtivos    = Math.Clamp(dto.UsuariosAtivos, 0, 100_000);
            hb.LimiteDispositivos= Math.Clamp(dto.LimiteDispositivos, 0, 100_000);
            hb.Os                = Trunc(dto.Os, 120);
            hb.StatusBackend     = Trunc(dto.StatusBackend, 20);
            hb.StatusPg          = Trunc(dto.StatusPg, 20);
            hb.Ip                = ip;
            if (cliente.Heartbeat is null) db.Heartbeats.Add(hb);

            // Espelha o limite no cadastro (informativo)
            cliente.LimiteDispositivos = dto.LimiteDispositivos;

            // Histórico enxuto
            db.HeartbeatHistorico.Add(new HeartbeatHistorico
            {
                ClienteId = cliente.Id, Ts = agora, Versao = dto.Versao, UsuariosAtivos = dto.UsuariosAtivos
            });

            // Saúde por indicador (upsert por handle)
            if (dto.Indicadores is { Count: > 0 })
            {
                var existentes = await db.IndicadoresSaude
                    .Where(i => i.ClienteId == cliente.Id).ToListAsync();
                // Teto de 200 indicadores por heartbeat (anti-abuso de storage).
                foreach (var ind in dto.Indicadores.Take(200))
                {
                    var handle = Trunc(ind.Handle, 80);
                    if (string.IsNullOrWhiteSpace(handle)) continue;
                    var alvo = existentes.FirstOrDefault(x => x.Handle == handle);
                    if (alvo is null)
                    {
                        alvo = new IndicadorSaude { ClienteId = cliente.Id, Handle = handle };
                        db.IndicadoresSaude.Add(alvo);
                    }
                    alvo.Status        = Trunc(ind.Status, 20) ?? "";
                    alvo.UltimoSucesso = ind.UltimoSucesso ?? alvo.UltimoSucesso;
                    alvo.UltimoErro    = ind.UltimoErro ?? alvo.UltimoErro;
                    alvo.Mensagem      = Trunc(ind.Mensagem, 500);
                    alvo.AtualizadoEm  = agora;
                }
            }

            await db.SaveChangesAsync();
            return Results.NoContent();
        }).RequireRateLimiting("telemetria");
    }

    // Limita o tamanho de strings vindas do cliente (evita abuso/inflar storage).
    private static string? Trunc(string? s, int max)
    {
        if (string.IsNullOrEmpty(s)) return s;
        s = s.Trim();
        return s.Length <= max ? s : s.Substring(0, max);
    }
}
