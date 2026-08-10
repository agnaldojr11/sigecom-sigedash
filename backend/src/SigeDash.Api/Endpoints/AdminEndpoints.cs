using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;
using SigeDash.Api.Modelos;
using SigeDash.Api.Seguranca;

namespace SigeDash.Api.Endpoints;

public record CriarClienteRequest(string Nome, int CodigoEmpresa, string NomeLoja, string? AdminLogin = null, int LimiteDispositivos = 0);
public record ResetSenhaRequest(string Login, string? Cliente = null);
public record DefinirLimiteRequest(int Limite, string? Cliente = null);

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
            var cliente = new Cliente { Nome = r.Nome, ChaveApi = chave, Ativo = true, LimiteDispositivos = r.LimiteDispositivos };
            db.Clientes.Add(cliente);
            await db.SaveChangesAsync();

            db.Lojas.Add(new Loja
            {
                ClienteId = cliente.Id,
                CodigoEmpresa = r.CodigoEmpresa,
                Nome = r.NomeLoja
            });

            // Cria o ADMIN inicial da empresa (primeiro acesso). Senha temporaria forte,
            // com troca obrigatoria no 1o login. Devolvida UMA vez para o instalador imprimir.
            var adminLogin = string.IsNullOrWhiteSpace(r.AdminLogin) ? "admin" : r.AdminLogin!.Trim();
            var senhaTemp  = Senhas.GerarTemporaria();
            db.UsuariosApp.Add(new UsuarioApp
            {
                ClienteId          = cliente.Id,
                Login              = adminLogin,
                NomeExibicao       = "Administrador",
                SenhaHash          = Senhas.Hash(senhaTemp),
                EhAdmin            = true,
                Ativo              = true,
                PrecisaTrocarSenha = true,
                CriadoEm           = DateTime.UtcNow
            });
            await db.SaveChangesAsync();

            return Results.Ok(new
            {
                clienteId = cliente.Id,
                nome      = cliente.Nome,
                chaveApi  = cliente.ChaveApi,
                adminLogin,
                adminSenhaTemporaria = senhaTemp,
                mensagem  = "Configure o agente com a ChaveApi. Entregue o login/senha do ADM ao dono (troca obrigatoria no 1o acesso)."
            });
        });

        // ── GET /admin/clientes ───────────────────────────────────────────────
        admin.MapGet("/clientes", async (AppDbContext db) =>
            await db.Clientes
                .Select(c => new { c.Id, c.Nome, c.ChaveApi, c.Ativo, c.LimiteDispositivos })
                .ToListAsync());

        // ── POST /admin/limite-dispositivos ───────────────────────────────────
        // Define/ajusta o limite de usuarios (seats/dispositivos) do plano. SO pela SistemasBr
        // (X-Admin-Key + gate "somente local"). O admin do cliente nunca altera — apenas visualiza.
        // Usado no install e pelo definir-limite.ps1 quando o cliente compra mais licencas.
        admin.MapPost("/limite-dispositivos", async (DefinirLimiteRequest r, AppDbContext db) =>
        {
            if (r.Limite < 0) return Results.BadRequest(new { erro = "Limite invalido (use 0 para ilimitado)." });

            Cliente? cliente;
            if (!string.IsNullOrWhiteSpace(r.Cliente))
                cliente = await db.Clientes.FirstOrDefaultAsync(c => c.Nome == r.Cliente);
            else
            {
                var dois = await db.Clientes.Take(2).ToListAsync();
                if (dois.Count != 1) return Results.BadRequest(new { erro = "Ha mais de um cliente; informe 'cliente'." });
                cliente = dois[0];
            }
            if (cliente is null) return Results.NotFound(new { erro = "Cliente nao encontrado." });

            cliente.LimiteDispositivos = r.Limite;
            await db.SaveChangesAsync();
            var ativos = await db.UsuariosApp.CountAsync(u => u.ClienteId == cliente.Id && u.Ativo);
            return Results.Ok(new { cliente = cliente.Nome, limiteDispositivos = cliente.LimiteDispositivos, usuariosAtivos = ativos });
        });

        // ── POST /admin/reset-senha ───────────────────────────────────────────
        // Recuperacao LOCAL (no servidor do cliente) quando o ADM perde a senha e nao ha
        // outro admin para reseta-lo. Protegido por X-Admin-Key + gate "somente local"
        // (bloqueado via tunnel). Gera senha temporaria (troca obrigatoria no proximo login).
        // Chamado pelo resetar-senha.ps1 rodando na propria maquina.
        admin.MapPost("/reset-senha", async (ResetSenhaRequest r, AppDbContext db) =>
        {
            Cliente? cliente;
            if (!string.IsNullOrWhiteSpace(r.Cliente))
                cliente = await db.Clientes.FirstOrDefaultAsync(c => c.Nome == r.Cliente);
            else
            {
                // Servidor de cliente normalmente tem 1 cliente; se houver mais, exige informar.
                var dois = await db.Clientes.Take(2).ToListAsync();
                if (dois.Count != 1) return Results.BadRequest(new { erro = "Ha mais de um cliente; informe 'cliente'." });
                cliente = dois[0];
            }
            if (cliente is null) return Results.NotFound(new { erro = "Cliente nao encontrado." });

            var login = (r.Login ?? "").Trim();
            var user = await db.UsuariosApp.FirstOrDefaultAsync(u => u.ClienteId == cliente.Id && u.Login == login);
            if (user is null) return Results.NotFound(new { erro = $"Usuario '{login}' nao encontrado." });

            var senha = Senhas.GerarTemporaria();
            user.SenhaHash          = Senhas.Hash(senha);
            user.PrecisaTrocarSenha = true;   // troca obrigatoria no proximo login
            user.BloqueadoAte       = null;
            user.TentativasFalhas   = 0;
            user.SessaoToken        = null;   // derruba qualquer sessao ativa
            user.AtualizadoEm       = DateTime.UtcNow;
            await db.SaveChangesAsync();
            return Results.Ok(new { cliente = cliente.Nome, login = user.Login, senhaTemporaria = senha });
        });
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
