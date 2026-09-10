using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Modelos;
using SigeDash.Central.Servicos;

namespace SigeDash.Central.Endpoints;

public record LiberarDto(bool Liberada);

/// <summary>
/// Menu VERSÕES — catálogo das releases (GitHub) para o suporte/implementação. Curadoria por tag
/// (liberar/ocultar) e download via link temporário assinado do GitHub (não passa pela Central).
/// Tudo requer login no painel.
/// </summary>
public static class VersoesEndpoints
{
    public static void MapVersoes(this IEndpointRouteBuilder app)
    {
        // Lista as releases + estado de liberação (curadoria).
        app.MapGet("/painel/versoes", async (GithubReleases gh, CentralDbContext db, CancellationToken ct) =>
        {
            if (!gh.Configurado)
                return Results.Json(new { erro = "Integração com o GitHub não configurada (defina Github__Token no Railway)." },
                    statusCode: StatusCodes.Status503ServiceUnavailable);

            IReadOnlyList<GithubReleases.Release> releases;
            try { releases = await gh.ListarAsync(ct); }
            catch (Exception ex) { return Results.Json(new { erro = "Falha ao consultar o GitHub: " + ex.Message }, statusCode: 502); }

            var liberadas = await db.VersoesLiberadas.ToDictionaryAsync(v => v.Tag, v => v, ct);

            var lista = releases
                .Where(r => !r.Draft)
                .Select(r => new
                {
                    tag = r.TagName,
                    nome = string.IsNullOrWhiteSpace(r.Name) ? r.TagName : r.Name,
                    notas = r.Body,
                    prerelease = r.Prerelease,
                    publicadoEm = r.PublishedAt,
                    liberada = liberadas.TryGetValue(r.TagName, out var vl) && vl.Liberada,
                    assets = r.Assets.Select(a => new { a.Id, a.Name, a.Size }).ToList()
                })
                .ToList();

            return Results.Ok(lista);
        }).RequireAuthorization();

        // Curadoria: libera/oculta uma versão para o suporte (qualquer usuário do painel).
        app.MapPost("/painel/versoes/{tag}/liberar", async (
            string tag, LiberarDto dto, ClaimsPrincipal user, CentralDbContext db, CancellationToken ct) =>
        {
            var vl = await db.VersoesLiberadas.FirstOrDefaultAsync(v => v.Tag == tag, ct);
            if (vl is null)
            {
                vl = new VersaoLiberada { Tag = tag };
                db.VersoesLiberadas.Add(vl);
            }
            vl.Liberada = dto.Liberada;
            vl.AtualizadoEm = DateTime.UtcNow;
            vl.AtualizadoPor = user.FindFirstValue("login") ?? user.Identity?.Name;
            await db.SaveChangesAsync(ct);
            return Results.Ok(new { tag, liberada = vl.Liberada });
        }).RequireAuthorization();

        // Download: resolve o link temporário assinado do GitHub. Só para versões liberadas
        // (evita distribuir uma release que ainda não passou pela curadoria).
        app.MapGet("/painel/versoes/{tag}/asset/{assetId:long}/link", async (
            string tag, long assetId, GithubReleases gh, CentralDbContext db, CancellationToken ct) =>
        {
            if (!gh.Configurado) return Results.Json(new { erro = "GitHub não configurado." }, statusCode: 503);

            var vl = await db.VersoesLiberadas.FirstOrDefaultAsync(v => v.Tag == tag, ct);
            if (vl is null || !vl.Liberada)
                return Results.Json(new { erro = "Versão não liberada para download." }, statusCode: 403);

            // Confere que o asset realmente pertence a essa tag (não confia só no id da URL).
            var releases = await gh.ListarAsync(ct);
            var rel = releases.FirstOrDefault(r => r.TagName == tag);
            if (rel is null || rel.Assets.All(a => a.Id != assetId))
                return Results.NotFound(new { erro = "Asset não encontrado nesta versão." });

            var url = await gh.ResolverDownloadAsync(assetId, ct);
            if (string.IsNullOrWhiteSpace(url))
                return Results.Json(new { erro = "Não foi possível gerar o link de download." }, statusCode: 502);

            return Results.Ok(new { url });
        }).RequireAuthorization();
    }
}
