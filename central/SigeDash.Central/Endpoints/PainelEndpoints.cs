using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Seguranca;

namespace SigeDash.Central.Endpoints;

public record LoginDto(string Login, string Senha);

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
            if (u is null || !Auth.ConfereSenha(dto.Senha ?? "", u.SenhaHash))
                return Results.Json(new { erro = "Usuário ou senha inválidos." }, statusCode: 401);

            u.UltimoLoginEm = DateTime.UtcNow;
            await db.SaveChangesAsync();
            return Results.Ok(new { token = Auth.GerarToken(jwtSecret, u.Login), login = u.Login });
        });

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

            return Results.Ok(new
            {
                c.Id, c.Nome, c.Cnpj, c.LimiteDispositivos, c.CriadoEm, c.Observacao,
                online,
                heartbeat = c.Heartbeat,
                indicadores = c.Indicadores.OrderBy(i => i.Handle),
                historico = hist
            });
        }).RequireAuthorization();
    }

    private static Version ParseVersao(string? v)
    {
        return Version.TryParse((v ?? "").TrimStart('v', 'V'), out var r) ? r : new Version(0, 0, 0);
    }
}
