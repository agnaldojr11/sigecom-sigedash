using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Modelos;
using SigeDash.Central.Seguranca;

namespace SigeDash.Central.Endpoints;

public record LoginDto(string Login, string Senha);
public record EstadoDto(string Estado, string? Motivo, DateTime? ExpiraEm);
public record LimiteDto(int Limite);

/// <summary>API do painel interno (SistemasBr). Login por JWT; leitura da frota.</summary>
public static class PainelEndpoints
{
    // Considera-se OFFLINE se o último heartbeat passou disto (3x a cadência de 3 min + folga).
    private static readonly TimeSpan LimiteOnline = TimeSpan.FromMinutes(12);

    public static void MapPainel(this IEndpointRouteBuilder app, IConfiguration cfg)
    {
        var jwtSecret = cfg["Jwt:SecretKey"] ?? "";

        app.MapPost("/painel/login", async (LoginDto dto, CentralDbContext db) =>
        {
            var login = (dto.Login ?? "").Trim();
            var u = await db.UsuariosPainel.FirstOrDefaultAsync(x => x.Login == login);

            // Lockout: 5 falhas → 15 min bloqueado.
            if (u is not null && u.BloqueadoAte is { } ate && ate > DateTime.UtcNow)
                return Results.Json(new { erro = "Muitas tentativas. Tente novamente em alguns minutos." },
                                    statusCode: StatusCodes.Status429TooManyRequests);

            if (u is null || !Auth.ConfereSenha(dto.Senha ?? "", u.SenhaHash))
            {
                if (u is not null)
                {
                    u.TentativasFalhas++;
                    if (u.TentativasFalhas >= 5) { u.BloqueadoAte = DateTime.UtcNow.AddMinutes(15); u.TentativasFalhas = 0; }
                    await db.SaveChangesAsync();
                }
                return Results.Json(new { erro = "Usuário ou senha inválidos." }, statusCode: 401);
            }

            u.TentativasFalhas = 0;
            u.BloqueadoAte = null;
            u.UltimoLoginEm = DateTime.UtcNow;
            await db.SaveChangesAsync();
            return Results.Ok(new { token = Auth.GerarToken(jwtSecret, u.Login), login = u.Login });
        }).RequireRateLimiting("login");

        // Resumo da frota (dashboard)
        app.MapGet("/painel/frota", async (CentralDbContext db) =>
        {
            var agora = DateTime.UtcNow;
            var clientes = await db.Clientes
                .Include(c => c.Heartbeat)
                .Include(c => c.Indicadores)
                .OrderBy(c => c.Nome)
                .ToListAsync();

            // "versão mais nova vista na frota" = referência para marcar desatualizados
            var versaoTopo = clientes
                .Select(c => c.Heartbeat?.Versao)
                .Where(v => !string.IsNullOrWhiteSpace(v))
                .Select(ParseVersao)
                .DefaultIfEmpty(new Version(0, 0, 0))
                .Max();

            var lista = clientes.Select(c =>
            {
                var hb = c.Heartbeat;
                var online = hb != null && (agora - hb.RecebidoEm) <= LimiteOnline;
                var ver = hb?.Versao;
                var desatualizado = ver != null && ParseVersao(ver) < versaoTopo;
                var indErro = c.Indicadores.Count(i => i.Status == "erro");
                return new
                {
                    c.Id, c.Nome, c.Cnpj,
                    online,
                    estado = c.Estado,
                    versao = ver,
                    desatualizado,
                    usuariosAtivos = hb?.UsuariosAtivos ?? 0,
                    limite = c.LimiteDispositivos,
                    indicadoresErro = indErro,
                    ultimoHeartbeat = hb?.RecebidoEm,
                    uptimeSeg = hb?.UptimeSeg ?? 0,
                    statusPg = hb?.StatusPg
                };
            }).ToList();

            var resumo = new
            {
                total = lista.Count,
                online = lista.Count(x => x.online),
                offline = lista.Count(x => !x.online),
                desatualizados = lista.Count(x => x.desatualizado),
                suspensos = lista.Count(x => EstadoAssinatura.Bloqueia(x.estado)),
                comAlertas = lista.Count(x => !x.online || x.desatualizado || x.indicadoresErro > 0),
                versaoTopo = versaoTopo.ToString()
            };
            return Results.Ok(new { resumo, clientes = lista });
        }).RequireAuthorization();

        // Detalhe de um cliente
        app.MapGet("/painel/clientes/{id:int}", async (int id, CentralDbContext db) =>
        {
            var c = await db.Clientes
                .Include(x => x.Heartbeat)
                .Include(x => x.Indicadores)
                .FirstOrDefaultAsync(x => x.Id == id);
            if (c is null) return Results.NotFound();

            var hist = await db.HeartbeatHistorico
                .Where(h => h.ClienteId == id)
                .OrderByDescending(h => h.Ts).Take(200)
                .OrderBy(h => h.Ts)
                .Select(h => new { h.Ts, h.UsuariosAtivos, h.Versao })
                .ToListAsync();

            var agora = DateTime.UtcNow;
            var online = c.Heartbeat != null && (agora - c.Heartbeat.RecebidoEm) <= LimiteOnline;

            // Histórico das ações (assinatura + limite de dispositivos), para consulta posterior.
            var auditoria = await db.LogsAuditoria
                .Where(l => l.ClienteId == id && (l.Acao == "estado_assinatura" || l.Acao == "limite_dispositivos"))
                .OrderByDescending(l => l.Ts).Take(50)
                .Select(l => new { l.Ts, l.Usuario, l.Detalhe })
                .ToListAsync();

            return Results.Ok(new
            {
                c.Id, c.Nome, c.Cnpj, c.LimiteDispositivos, c.CriadoEm, c.Observacao,
                online,
                c.Estado, c.ExpiraEm, c.MotivoBloqueio, c.EstadoAtualizadoEm, c.EstadoPor,
                c.LimiteGerenciadoCentral, c.LimiteAtualizadoEm, c.LimitePor,
                usuariosAtivos = c.Heartbeat?.UsuariosAtivos ?? 0,
                heartbeat = c.Heartbeat,
                indicadores = c.Indicadores.OrderBy(i => i.Handle),
                historico = hist,
                auditoria
            });
        }).RequireAuthorization();

        // Define o limite de dispositivos (libera/ajusta acessos). A Central vira a fonte do limite
        // e o cliente aplica no próximo heartbeat — só para ESTE cliente (heartbeat é por ChaveTelemetria).
        app.MapPost("/painel/clientes/{id:int}/limite", async (
            int id, LimiteDto dto, ClaimsPrincipal user, CentralDbContext db) =>
        {
            if (dto.Limite < 0)
                return Results.BadRequest(new { erro = "Limite inválido (use 0 para ilimitado)." });

            var c = await db.Clientes.Include(x => x.Heartbeat).FirstOrDefaultAsync(x => x.Id == id);
            if (c is null) return Results.NotFound();

            // Nunca abaixo dos dispositivos já em uso (0 = ilimitado é sempre permitido).
            var emUso = c.Heartbeat?.UsuariosAtivos ?? 0;
            if (dto.Limite != 0 && dto.Limite < emUso)
                return Results.BadRequest(new { erro = $"O cliente já usa {emUso} dispositivo(s). Defina 0 (ilimitado) ou um valor ≥ {emUso}." });

            var quem = user.FindFirstValue("login") ?? user.Identity?.Name ?? "?";
            var anterior = c.LimiteDispositivos;

            c.LimiteDispositivos = dto.Limite;
            c.LimiteGerenciadoCentral = true;
            c.LimiteAtualizadoEm = DateTime.UtcNow;
            c.LimitePor = quem;

            db.LogsAuditoria.Add(new LogAuditoria
            {
                Usuario = quem,
                Acao = "limite_dispositivos",
                ClienteId = c.Id,
                Detalhe = $"{c.Nome}: limite {anterior} → {dto.Limite}"
            });
            await db.SaveChangesAsync();

            return Results.Ok(new { c.Id, c.LimiteDispositivos, c.LimiteGerenciadoCentral, c.LimiteAtualizadoEm, c.LimitePor });
        }).RequireAuthorization();

        // Muda o estado da assinatura (kill-switch). O cliente aplica no próximo heartbeat.
        app.MapPost("/painel/clientes/{id:int}/estado", async (
            int id, EstadoDto dto, ClaimsPrincipal user, CentralDbContext db) =>
        {
            var estado = (dto.Estado ?? "").Trim().ToLowerInvariant();
            if (!EstadoAssinatura.Todos.Contains(estado))
                return Results.BadRequest(new { erro = "Estado inválido. Use: " + string.Join(", ", EstadoAssinatura.Todos) });

            var motivo = (dto.Motivo ?? "").Trim();
            if (motivo.Length < 3)
                return Results.BadRequest(new { erro = "Informe o motivo da mudança (mín. 3 caracteres)." });

            var c = await db.Clientes.FirstOrDefaultAsync(x => x.Id == id);
            if (c is null) return Results.NotFound();

            var quem = user.FindFirstValue("login") ?? user.Identity?.Name ?? "?";
            var anterior = c.Estado;

            c.Estado = estado;
            // MotivoBloqueio (mostrado ao cliente) só faz sentido quando o estado bloqueia; o motivo
            // sempre fica registrado na auditoria abaixo.
            c.MotivoBloqueio = EstadoAssinatura.Bloqueia(estado) ? motivo : null;
            c.ExpiraEm = dto.ExpiraEm;
            c.EstadoAtualizadoEm = DateTime.UtcNow;
            c.EstadoPor = quem;

            db.LogsAuditoria.Add(new LogAuditoria
            {
                Usuario = quem,
                Acao = "estado_assinatura",
                ClienteId = c.Id,
                Detalhe = $"{c.Nome}: {anterior} → {estado} ({motivo})"
            });
            await db.SaveChangesAsync();

            return Results.Ok(new { c.Id, c.Estado, c.MotivoBloqueio, c.ExpiraEm, c.EstadoPor, c.EstadoAtualizadoEm });
        }).RequireAuthorization();
    }

    private static Version ParseVersao(string? v)
    {
        return Version.TryParse((v ?? "").TrimStart('v', 'V'), out var r) ? r : new Version(0, 0, 0);
    }
}
