using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;

namespace SigeDash.Api.Endpoints;

/// <summary>Entrega ao PWA o ultimo snapshot de cada indicador do cliente logado.</summary>
public static class DashboardEndpoints
{
    public static void MapDashboards(this IEndpointRouteBuilder app)
    {
        // lista o indicador mais recente de cada handle
        app.MapGet("/dash/{codigoEmpresa:int}", async (int codigoEmpresa, ClaimsPrincipal user, AppDbContext db) =>
        {
            var clienteId = int.Parse(user.FindFirstValue("cliente_id")!);
            var usuarioId = int.Parse(user.FindFirstValue("usuario_id")!);

            // Permissoes frescas do banco (mudanca do admin vale no proximo refresh, sem esperar o token expirar)
            var usuario = await db.UsuariosApp.FirstOrDefaultAsync(u => u.Id == usuarioId && u.ClienteId == clienteId);
            if (usuario is null) return Results.Unauthorized();
            var secoes = Permissoes.SecoesEfetivas(usuario);

            // ultimo snapshot por handle (FB-friendly seria distinct; aqui em PG usamos group/max)
            var ultimos = await db.Snapshots
                .Where(s => s.ClienteId == clienteId && s.CodigoEmpresa == codigoEmpresa)
                .GroupBy(s => s.IndicadorHandle)
                .Select(g => g.OrderByDescending(s => s.GeradoEm).First())
                .ToListAsync();

            // Trava de seguranca: so devolve os snapshots das secoes permitidas e ajusta o
            // payload conforme sub-permissoes (ex.: remove "custo" da pesquisa sem estoque_custo).
            var resp = ultimos
                .Where(s => Permissoes.PodeVerHandle(s.IndicadorHandle, secoes))
                .Select(s => new
                {
                    s.IndicadorHandle,
                    s.GeradoEm,
                    payload = Permissoes.AjustarPayload(s.IndicadorHandle, s.PayloadJson, secoes)
                });
            return Results.Ok(resp);
        }).RequireAuthorization();
    }
}
