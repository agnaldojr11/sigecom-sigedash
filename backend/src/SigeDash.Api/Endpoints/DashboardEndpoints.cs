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

            // ultimo snapshot por handle (FB-friendly seria distinct; aqui em PG usamos group/max)
            var ultimos = await db.Snapshots
                .Where(s => s.ClienteId == clienteId && s.CodigoEmpresa == codigoEmpresa)
                .GroupBy(s => s.IndicadorHandle)
                .Select(g => g.OrderByDescending(s => s.GeradoEm).First())
                .ToListAsync();

            // payload ja e JSON pronto; devolvemos como esta
            var resp = ultimos.Select(s => new
            {
                s.IndicadorHandle, s.GeradoEm, payload = s.PayloadJson
            });
            return Results.Ok(resp);
        }).RequireAuthorization();
    }
}
