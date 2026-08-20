using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Modelos;
using SigeDash.Central.Seguranca;

namespace SigeDash.Central.Endpoints;

public record RegistrarClienteDto(string Nome, string? Cnpj, int LimiteDispositivos, string? Observacao);

/// <summary>
/// Administração da frota (SistemasBr). Protegido por X-Admin-Key (config Central:AdminKey).
/// Registra cada cliente e devolve a ChaveTelemetria — que vai no appsettings do backend do cliente.
/// </summary>
public static class AdminCentralEndpoints
{
    public static void MapAdminCentral(this IEndpointRouteBuilder app, IConfiguration cfg)
    {
        var grupo = app.MapGroup("/admin").AddEndpointFilter(async (ctx, next) =>
        {
            var adminKey = cfg["Central:AdminKey"];
            if (string.IsNullOrWhiteSpace(adminKey))
                return Results.Problem("Central:AdminKey não configurada.", statusCode: 500);
            if (ctx.HttpContext.Request.Headers["X-Admin-Key"].ToString() != adminKey)
                return Results.Unauthorized();
            return await next(ctx);
        });

        // Registra um novo cliente na frota → retorna a chave de telemetria (uma vez).
        grupo.MapPost("/clientes", async (RegistrarClienteDto dto, CentralDbContext db) =>
        {
            var nome = (dto.Nome ?? "").Trim();
            if (nome.Length == 0) return Results.BadRequest(new { erro = "Informe o nome." });
            if (await db.Clientes.AnyAsync(c => c.Nome == nome))
                return Results.Conflict(new { erro = $"Cliente '{nome}' já existe." });

            var cliente = new ClienteCentral
            {
                Nome = nome,
                Cnpj = string.IsNullOrWhiteSpace(dto.Cnpj) ? null : dto.Cnpj!.Trim(),
                ChaveTelemetria = Auth.GerarChaveTelemetria(),
                LimiteDispositivos = dto.LimiteDispositivos,
                Observacao = dto.Observacao,
                Ativo = true
            };
            db.Clientes.Add(cliente);
            await db.SaveChangesAsync();

            return Results.Ok(new
            {
                cliente.Id, cliente.Nome, chaveTelemetria = cliente.ChaveTelemetria,
                mensagem = "Coloque esta ChaveTelemetria no appsettings.Production.json do backend do cliente (Central:ChaveTelemetria)."
            });
        });

        // Lista clientes (com chaves) para conferência/setup.
        grupo.MapGet("/clientes", async (CentralDbContext db) =>
            await db.Clientes
                .Select(c => new { c.Id, c.Nome, c.Cnpj, c.ChaveTelemetria, c.LimiteDispositivos, c.Ativo })
                .OrderBy(c => c.Nome).ToListAsync());

        // Gera nova chave (revoga a anterior).
        grupo.MapPost("/clientes/{id:int}/rotacionar-chave", async (int id, CentralDbContext db) =>
        {
            var c = await db.Clientes.FindAsync(id);
            if (c is null) return Results.NotFound();
            c.ChaveTelemetria = Auth.GerarChaveTelemetria();
            await db.SaveChangesAsync();
            return Results.Ok(new { c.Id, c.Nome, chaveTelemetria = c.ChaveTelemetria });
        });
    }
}
