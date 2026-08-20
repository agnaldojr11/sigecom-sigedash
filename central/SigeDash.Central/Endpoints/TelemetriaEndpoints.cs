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
            hb.Versao            = dto.Versao;
            hb.UptimeSeg         = dto.UptimeSeg;
            hb.UsuariosAtivos    = dto.UsuariosAtivos;
            hb.LimiteDispositivos= dto.LimiteDispositivos;
            hb.Os                = dto.Os;
            hb.StatusBackend     = dto.StatusBackend;
            hb.StatusPg          = dto.StatusPg;
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
                foreach (var ind in dto.Indicadores)
                {
                    if (string.IsNullOrWhiteSpace(ind.Handle)) continue;
                    var alvo = existentes.FirstOrDefault(x => x.Handle == ind.Handle);
                    if (alvo is null)
                    {
                        alvo = new IndicadorSaude { ClienteId = cliente.Id, Handle = ind.Handle };
                        db.IndicadoresSaude.Add(alvo);
                    }
                    alvo.Status        = ind.Status ?? "";
                    alvo.UltimoSucesso = ind.UltimoSucesso ?? alvo.UltimoSucesso;
                    alvo.UltimoErro    = ind.UltimoErro ?? alvo.UltimoErro;
                    alvo.Mensagem      = ind.Mensagem;
                    alvo.AtualizadoEm  = agora;
                }
            }

            await db.SaveChangesAsync();
            return Results.NoContent();
        });
    }
}
