using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using SigeDash.Api.Data;

namespace SigeDash.Api.Endpoints;

public record LoginRequest(string Cliente, string Login, string Senha);

/// <summary>Login do usuario do app. Devolve JWT curto usado pelo PWA.</summary>
public static class AuthEndpoints
{
    public static void MapAuth(this IEndpointRouteBuilder app, IConfiguration cfg)
    {
        app.MapPost("/auth/login", async (LoginRequest r, AppDbContext db) =>
        {
            var cliente = await db.Clientes.FirstOrDefaultAsync(c => c.Nome == r.Cliente && c.Ativo);
            if (cliente is null) return Results.Unauthorized();

            var user = await db.UsuariosApp
                .FirstOrDefaultAsync(u => u.ClienteId == cliente.Id && u.Login == r.Login);
            if (user is null || !BCrypt.Net.BCrypt.Verify(r.Senha, user.SenhaHash))
                return Results.Unauthorized();

            var token = GerarJwt(cfg, cliente.Id, user.Login, user.Departamento);
            return Results.Ok(new { token, cliente = cliente.Nome, departamento = user.Departamento });
        });
    }

    private static string GerarJwt(IConfiguration cfg, int clienteId, string login, string? depto)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(cfg["Jwt:SecretKey"]!));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var claims = new[]
        {
            new Claim("cliente_id", clienteId.ToString()),
            new Claim(ClaimTypes.Name, login),
            new Claim("departamento", depto ?? "")
        };
        var jwt = new JwtSecurityToken(
            issuer: cfg["Jwt:Issuer"], audience: cfg["Jwt:Audience"],
            claims: claims, expires: DateTime.UtcNow.AddHours(8), signingCredentials: creds);
        return new JwtSecurityTokenHandler().WriteToken(jwt);
    }
}
