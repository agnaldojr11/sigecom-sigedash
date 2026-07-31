using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using SigeDash.Api.Data;
using SigeDash.Api.Seguranca;

namespace SigeDash.Api.Endpoints;

public record LoginRequest(string Cliente, string Login, string Senha);
public record TrocarSenhaRequest(string SenhaAtual, string SenhaNova);

public static class AuthEndpoints
{
    // Anti-forca-bruta (alem do rate limit da policy "login").
    private const int LimiteTentativas = 5;
    private const int BloqueioMinutos  = 15;

    public static void MapAuth(this IEndpointRouteBuilder app, IConfiguration cfg)
    {
        // Lista de empresas cadastradas — usado para popular o dropdown do login no PWA
        app.MapGet("/auth/empresas", async (AppDbContext db) =>
        {
            var lista = await db.Clientes
                .Where(c => c.Ativo)
                .OrderBy(c => c.Nome)
                .Select(c => new { c.Id, c.Nome })
                .ToListAsync();
            return Results.Ok(lista);
        });

        app.MapPost("/auth/login", async (LoginRequest r, AppDbContext db) =>
        {
            var invalido = Results.Json(new { erro = "Usuario ou senha invalidos." }, statusCode: StatusCodes.Status401Unauthorized);

            var cliente = await db.Clientes.FirstOrDefaultAsync(c => c.Nome == r.Cliente && c.Ativo);
            if (cliente is null) return invalido;

            var user = await db.UsuariosApp
                .FirstOrDefaultAsync(u => u.ClienteId == cliente.Id && u.Login == r.Login);
            // Mensagem generica p/ usuario inexistente/inativo (evita enumeracao).
            if (user is null || !user.Ativo) return invalido;

            // Bloqueio temporario por tentativas
            if (user.BloqueadoAte is { } ate && ate > DateTime.UtcNow)
            {
                var faltam = (int)Math.Ceiling((ate - DateTime.UtcNow).TotalMinutes);
                return Results.Json(new { erro = $"Muitas tentativas. Tente novamente em ~{faltam} min." },
                    statusCode: StatusCodes.Status429TooManyRequests);
            }

            if (!Senhas.Conferir(r.Senha, user.SenhaHash))
            {
                user.TentativasFalhas++;
                if (user.TentativasFalhas >= LimiteTentativas)
                {
                    user.BloqueadoAte = DateTime.UtcNow.AddMinutes(BloqueioMinutos);
                    user.TentativasFalhas = 0;
                }
                await db.SaveChangesAsync();
                return invalido;
            }

            // Sucesso: zera contadores, registra acesso e abre sessao unica (novo sid).
            user.TentativasFalhas = 0;
            user.BloqueadoAte     = null;
            user.UltimoLoginEm    = DateTime.UtcNow;
            var sid = Guid.NewGuid().ToString("N");
            user.SessaoToken = sid;
            await db.SaveChangesAsync();

            var admin  = Permissoes.EhAdmin(user);
            var secoes = Permissoes.SecoesEfetivas(user).ToArray();
            var token  = GerarJwt(cfg, cliente.Id, user.Id, user.Login, admin, sid);
            return Results.Ok(new { token, cliente = cliente.Nome, admin, secoes, precisaTrocarSenha = user.PrecisaTrocarSenha });
        }).RequireRateLimiting("login");

        // Troca da propria senha (primeiro acesso ou por vontade do usuario). Requer login.
        app.MapPost("/auth/trocar-senha", async (TrocarSenhaRequest r, ClaimsPrincipal principal, AppDbContext db) =>
        {
            if (!int.TryParse(principal.FindFirstValue("usuario_id"), out var uid)) return Results.Unauthorized();
            var user = await db.UsuariosApp.FirstOrDefaultAsync(u => u.Id == uid);
            if (user is null || !user.Ativo) return Results.Unauthorized();

            if (!Senhas.Conferir(r.SenhaAtual, user.SenhaHash))
                return Results.Json(new { erro = "Senha atual incorreta." }, statusCode: StatusCodes.Status400BadRequest);

            var erro = Senhas.Validar(r.SenhaNova);
            if (erro is not null) return Results.Json(new { erro }, statusCode: StatusCodes.Status400BadRequest);
            if (Senhas.Conferir(r.SenhaNova, user.SenhaHash))
                return Results.Json(new { erro = "A nova senha deve ser diferente da atual." }, statusCode: StatusCodes.Status400BadRequest);

            user.SenhaHash          = Senhas.Hash(r.SenhaNova);
            user.PrecisaTrocarSenha = false;
            user.AtualizadoEm       = DateTime.UtcNow;
            await db.SaveChangesAsync();
            return Results.Ok(new { ok = true });
        }).RequireAuthorization();

        // Heartbeat leve de sessao: 200 se o token ainda e a sessao ativa; 401 (via OnTokenValidated)
        // se foi substituida por um login em outro dispositivo. Usado pelo PWA para derrubar rapido.
        app.MapGet("/auth/sessao", () => Results.Ok(new { ok = true })).RequireAuthorization();
    }

    private static string GerarJwt(IConfiguration cfg, int clienteId, int usuarioId, string login, bool admin, string sid)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(cfg["Jwt:SecretKey"]!));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var claims = new[]
        {
            new Claim("cliente_id", clienteId.ToString()),
            new Claim("usuario_id", usuarioId.ToString()),
            new Claim("admin", admin ? "1" : "0"),
            new Claim("sid", sid),
            new Claim(ClaimTypes.Name, login)
        };
        var jwt = new JwtSecurityToken(
            issuer: cfg["Jwt:Issuer"], audience: cfg["Jwt:Audience"],
            claims: claims, expires: DateTime.UtcNow.AddHours(8), signingCredentials: creds);
        return new JwtSecurityTokenHandler().WriteToken(jwt);
    }
}
