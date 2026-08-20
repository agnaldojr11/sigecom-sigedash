using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using SigeDash.Central.Data;
using SigeDash.Central.Endpoints;
using SigeDash.Central.Modelos;
using SigeDash.Central.Seguranca;

var builder = WebApplication.CreateBuilder(args);

// Railway injeta a porta em PORT — escutar em 0.0.0.0:$PORT (senão 8080 local).
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");

// Connection string: Railway fornece DATABASE_URL (postgresql://...). Converte p/ formato Npgsql.
var conn = ResolverConexao(builder.Configuration);
builder.Services.AddDbContext<CentralDbContext>(o => o.UseNpgsql(conn));

// JWT do painel
var jwtSecret = builder.Configuration["Jwt:SecretKey"];
if (string.IsNullOrWhiteSpace(jwtSecret) || jwtSecret.Length < 32)
    jwtSecret = "DEV-ONLY-troque-por-uma-chave-longa-32+-em-producao!!";
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o => o.TokenValidationParameters = Auth.ValidationParams(jwtSecret));
builder.Services.AddAuthorization();

builder.Services.AddResponseCompression();

var app = builder.Build();

// Migra o banco + semeia o usuário do painel a partir das variáveis de ambiente.
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<CentralDbContext>();
    // Retry: no boot o Postgres do Railway pode ainda não aceitar conexões.
    for (var i = 1; i <= 10; i++)
    {
        try { db.Database.Migrate(); break; }
        catch (Exception ex) when (i < 10)
        {
            app.Logger.LogWarning("Postgres indisponível (tentativa {i}): {msg}", i, ex.Message);
            Thread.Sleep(3000);
        }
    }
    SemearAdmin(db, app.Configuration, app.Logger);
}

app.UseResponseCompression();
app.UseDefaultFiles();
app.UseStaticFiles();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new { ok = true, servico = "sigedash-central" }));
app.MapTelemetria();
app.MapPainel(app.Configuration);
app.MapAdminCentral(app.Configuration);

app.MapFallbackToFile("index.html");

app.Run();


// ── Helpers ─────────────────────────────────────────────────────────────────
static string ResolverConexao(IConfiguration cfg)
{
    var url = Environment.GetEnvironmentVariable("DATABASE_URL");
    if (!string.IsNullOrWhiteSpace(url))
    {
        // postgresql://user:pass@host:port/dbname
        var uri = new Uri(url);
        var userInfo = uri.UserInfo.Split(':', 2);
        var sb = new NpgsqlConnectionStringBuilder
        {
            Host = uri.Host,
            Port = uri.Port <= 0 ? 5432 : uri.Port,
            Database = uri.AbsolutePath.TrimStart('/'),
            Username = Uri.UnescapeDataString(userInfo[0]),
            Password = userInfo.Length > 1 ? Uri.UnescapeDataString(userInfo[1]) : "",
            SslMode = SslMode.Prefer
        };
        return sb.ConnectionString;
    }
    return cfg.GetConnectionString("Postgres")
        ?? "Host=localhost;Port=5432;Database=sigedash_central;Username=postgres;Password=postgres";
}

static void SemearAdmin(CentralDbContext db, IConfiguration cfg, ILogger logger)
{
    var login = cfg["Painel:AdminLogin"] ?? "admin";
    var senha = cfg["Painel:AdminSenha"];
    if (string.IsNullOrWhiteSpace(senha))
    {
        logger.LogWarning("Painel:AdminSenha não definido — usuário do painel NÃO foi semeado. Defina a variável e reinicie.");
        return;
    }
    var existente = db.UsuariosPainel.FirstOrDefault(u => u.Login == login);
    if (existente is null)
    {
        db.UsuariosPainel.Add(new UsuarioPainel { Login = login, SenhaHash = Auth.HashSenha(senha) });
        db.SaveChanges();
        logger.LogInformation("Usuário do painel '{login}' criado.", login);
    }
    else
    {
        // Mantém a senha em dia com a variável de ambiente (permite reset trocando a env).
        existente.SenhaHash = Auth.HashSenha(senha);
        db.SaveChanges();
    }
}
