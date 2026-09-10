using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Modelos;
using SigeDash.Central.Seguranca;

namespace SigeDash.Central.Endpoints;

public record RegistrarDto(string Nome, string? Cnpj);

/// <summary>
/// Recebe o que a frota EMPURRA (phone-home). Autenticado por X-Telemetria-Key (chave por cliente).
/// Nenhum dado sensível/PII — só métrica operacional e status.
/// </summary>
public static class TelemetriaEndpoints
{
    public static void MapTelemetria(this IEndpointRouteBuilder app, IConfiguration cfg)
    {
        // Auto-registro (chamado pelo instalador/script do cliente, NÃO pelo heartbeat).
        // Autenticado pela chave de provisionamento compartilhada (X-Bootstrap-Key). Idempotente
        // por CNPJ (senão por Nome): reinstalar o mesmo cliente devolve a chave existente, não duplica.
        app.MapPost("/telemetria/registrar", async (RegistrarDto dto, HttpContext ctx, CentralDbContext db) =>
        {
            var bootstrap = cfg["Central:ChaveBootstrap"];
            if (string.IsNullOrWhiteSpace(bootstrap))
                return Results.Problem("Central:ChaveBootstrap não configurada.", statusCode: 503);
            var fornecida = ctx.Request.Headers["X-Bootstrap-Key"].ToString();
            if (!Auth.ChaveConfere(fornecida, bootstrap)) return Results.Unauthorized();

            var nome = (dto.Nome ?? "").Trim();
            if (nome.Length == 0) return Results.BadRequest(new { erro = "Informe o nome do cliente." });
            var cnpj = SoDigitos(dto.Cnpj);

            // Idempotência: acha por CNPJ (se houver) senão por Nome exato.
            ClienteCentral? c = null;
            if (cnpj is not null) c = await db.Clientes.FirstOrDefaultAsync(x => x.Cnpj == cnpj);
            c ??= await db.Clientes.FirstOrDefaultAsync(x => x.Nome == nome);

            var novo = c is null;
            if (novo)
            {
                c = new ClienteCentral { Nome = nome, Cnpj = cnpj, ChaveTelemetria = Auth.GerarChaveTelemetria(), Ativo = true };
                db.Clientes.Add(c);
            }
            else
            {
                // Completa dados faltantes sem sobrescrever o que já foi ajustado no painel.
                if (string.IsNullOrWhiteSpace(c!.Cnpj) && cnpj is not null) c.Cnpj = cnpj;
            }
            await db.SaveChangesAsync();

            return Results.Ok(new { c!.Id, c.Nome, chaveTelemetria = c.ChaveTelemetria, novo });
        }).RequireRateLimiting("admin");

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

            // Resposta do heartbeat = estado da assinatura (kill-switch por PULL). O backend do
            // cliente (v1.0.43+) lê isto e se auto-bloqueia se 'bloqueado'. Clientes antigos ignoram.
            var bloqueado = EstadoAssinatura.Bloqueia(cliente.Estado);
            return Results.Ok(new
            {
                assinatura = new
                {
                    estado = cliente.Estado,
                    bloqueado,
                    mensagem = bloqueado
                        ? (cliente.MotivoBloqueio ?? "Acesso suspenso. Entre em contato com a SistemasBr.")
                        : null,
                    expiraEm = cliente.ExpiraEm
                }
            });
        }).RequireRateLimiting("telemetria");
    }

    // Limita o tamanho de strings vindas do cliente (evita abuso/inflar storage).
    private static string? Trunc(string? s, int max)
    {
        if (string.IsNullOrEmpty(s)) return s;
        s = s.Trim();
        return s.Length <= max ? s : s.Substring(0, max);
    }

    // CNPJ normalizado (só dígitos) para idempotência; null se vazio.
    private static string? SoDigitos(string? s)
    {
        if (string.IsNullOrWhiteSpace(s)) return null;
        var d = new string(s.Where(char.IsDigit).ToArray());
        return d.Length == 0 ? null : d;
    }
}
