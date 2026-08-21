using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.IdentityModel.Tokens;

namespace SigeDash.Central.Seguranca;

/// <summary>JWT do painel + hashing/geração de segredos.</summary>
public static class Auth
{
    public const string Issuer = "sigedash-central";
    public const string Audience = "sigedash-painel";

    public static string GerarToken(string secret, string login)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var token = new JwtSecurityToken(
            issuer: Issuer, audience: Audience,
            claims: new[] { new Claim("login", login), new Claim(ClaimTypes.Name, login) },
            expires: DateTime.UtcNow.AddHours(8),
            signingCredentials: creds);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public static TokenValidationParameters ValidationParams(string secret) => new()
    {
        ValidateIssuer = true, ValidIssuer = Issuer,
        ValidateAudience = true, ValidAudience = Audience,
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secret)),
        ValidateLifetime = true, ClockSkew = TimeSpan.FromMinutes(2)
    };

    public static string HashSenha(string senha) => BCrypt.Net.BCrypt.HashPassword(senha, workFactor: 12);
    public static bool ConfereSenha(string senha, string hash)
    {
        try { return BCrypt.Net.BCrypt.Verify(senha, hash); } catch { return false; }
    }

    /// <summary>Comparação de chave/segredo em tempo constante (evita timing attack).</summary>
    public static bool ChaveConfere(string? fornecida, string? esperada)
    {
        var a = Encoding.UTF8.GetBytes(fornecida ?? "");
        var b = Encoding.UTF8.GetBytes(esperada ?? "");
        return CryptographicOperations.FixedTimeEquals(a, b);
    }

    /// <summary>Chave de telemetria url-safe (256 bits CSPRNG).</summary>
    public static string GerarChaveTelemetria()
    {
        var b = RandomNumberGenerator.GetBytes(32);
        var s = Convert.ToBase64String(b).Replace("+", "-").Replace("/", "_").TrimEnd('=');
        return $"SGT-{s}";
    }
}
