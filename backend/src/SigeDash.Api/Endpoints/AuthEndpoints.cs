using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using SigeDash.Api.Data;

namespace SigeDash.Api.Endpoints;

public record LoginRequest(string Cliente, string Login, string Senha);

public static class AuthEndpoints
{
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
            var cliente = await db.Clientes.FirstOrDefaultAsync(c => c.Nome == r.Cliente && c.Ativo);
            if (cliente is null) return Results.Unauthorized();

            var user = await db.UsuariosApp
                .FirstOrDefaultAsync(u => u.ClienteId == cliente.Id && u.Login == r.Login);
            if (user is null) return Results.Unauthorized();

            if (user.SenhaApp != Sha1Hex(r.Senha)) return Results.Unauthorized();

            // Sessao unica: gera um novo sid a cada login; invalida a sessao anterior deste usuario
            var sid = Guid.NewGuid().ToString("N");
            user.SessaoToken = sid;
            await db.SaveChangesAsync();

            var admin  = Permissoes.EhAdmin(user);
            var secoes = Permissoes.SecoesEfetivas(user).ToArray();
            var token  = GerarJwt(cfg, cliente.Id, user.Id, user.Login, admin, sid);
            return Results.Ok(new { token, cliente = cliente.Nome, admin, secoes });
        }).RequireRateLimiting("login");

        // Heartbeat leve de sessao: 200 se o token ainda e a sessao ativa; 401 (via OnTokenValidated)
        // se foi substituida por um login em outro dispositivo. Usado pelo PWA para derrubar rapido.
        app.MapGet("/auth/sessao", () => Results.Ok(new { ok = true })).RequireAuthorization();
    }

    private static string Sha1Hex(string s)
    {
        var hash = SHA1.HashData(Encoding.UTF8.GetBytes(s));
        return Convert.ToHexString(hash).ToLower();
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
