using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;
using SigeDash.Api.Modelos;

namespace SigeDash.Api.Endpoints;

public record CriarClienteRequest(string Nome, int CodigoEmpresa, string NomeLoja);

/// <summary>
/// Endpoints de administração — protegidos por X-Admin-Key (config AdminKey).
/// Usados pela equipe SistemasBr para cadastrar novos clientes.
/// Usuários são sincronizados automaticamente pelo agente via POST /ingest/usuarios.
/// </summary>
public static class AdminEndpoints
{
    public static void MapAdmin(this IEndpointRouteBuilder app, IConfiguration cfg)
    {
        var admin = app.MapGroup("/admin").AddEndpointFilter(AdminKeyFilter(cfg));

        // ── POST /admin/clientes ──────────────────────────────────────────────
        // Cria o cliente e retorna a ChaveApi gerada (necessária para configurar o agente).
        admin.MapPost("/clientes", async (CriarClienteRequest r, AppDbContext db) =>
        {
            if (await db.Clientes.AnyAsync(c => c.Nome == r.Nome))
                return Results.Conflict(new { erro = $"Cliente '{r.Nome}' já existe." });

            var chave = GerarChave();
            var cliente = new Cliente { Nome = r.Nome, ChaveApi = chave, Ativo = true };
            db.Clientes.Add(cliente);
            await db.SaveChangesAsync();

            db.Lojas.Add(new Loja
            {
                ClienteId = cliente.Id,
                CodigoEmpresa = r.CodigoEmpresa,
                Nome = r.NomeLoja
            });
            await db.SaveChangesAsync();

            return Results.Ok(new
            {
                clienteId = cliente.Id,
                nome      = cliente.Nome,
                chaveApi  = cliente.ChaveApi,
                mensagem  = "Configure o agente com a ChaveApi acima. Usuários serão sincronizados automaticamente."
            });
        });

        // ── GET /admin/clientes ───────────────────────────────────────────────
        admin.MapGet("/clientes", async (AppDbContext db) =>
            await db.Clientes
                .Select(c => new { c.Id, c.Nome, c.ChaveApi, c.Ativo })
                .ToListAsync());
    }

    private static string GerarChave()
    {
        // 256 bits de CSPRNG, url-safe. Sem prefixo derivado de dado publico (evita brute force dirigido).
        var bytes = RandomNumberGenerator.GetBytes(32);
        var rnd = Convert.ToBase64String(bytes).Replace("+", "-").Replace("/", "_").TrimEnd('=');
        return $"SGD-{rnd}";
    }

    private static Func<EndpointFilterInvocationContext, EndpointFilterDelegate, ValueTask<object?>> AdminKeyFilter(IConfiguration cfg)
        => async (ctx, next) =>
        {
            var adminKey = cfg["AdminKey"];
            if (string.IsNullOrEmpty(adminKey))
                return Results.Problem("AdminKey não configurada no servidor.", statusCode: 500);

            var headerKey = ctx.HttpContext.Request.Headers["X-Admin-Key"].ToString();
            if (headerKey != adminKey)
                return Results.Unauthorized();

            return await next(ctx);
        };
}
