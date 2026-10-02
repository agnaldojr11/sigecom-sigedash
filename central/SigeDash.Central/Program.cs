using System.Threading.RateLimiting;
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

// JWT do painel — FAIL-FAST: sem chave forte, o serviço NÃO sobe (nunca usa fallback público).
var jwtSecret = builder.Configuration["Jwt:SecretKey"];
if (string.IsNullOrWhiteSpace(jwtSecret) || jwtSecret.Length < 32)
    throw new InvalidOperationException(
        "Jwt:SecretKey ausente ou fraca (mínimo 32 caracteres). Defina a variável Jwt__SecretKey no Railway.");
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(o =>
    {
        o.TokenValidationParameters = Auth.ValidationParams(jwtSecret);
        // Revalida o usuario no banco a cada requisicao: desativar/excluir um usuario do painel
        // passa a ter efeito IMEDIATO (senao o token valeria ate expirar ~8h, inclusive para
        // kill-switch/limite/versoes nas rotas nao-admin). [Auditoria A1]
        o.Events = new JwtBearerEvents
        {
            OnTokenValidated = async ctx =>
            {
                var login = ctx.Principal?.FindFirst("login")?.Value;
                if (string.IsNullOrEmpty(login)) { ctx.Fail("token sem login"); return; }
                var db = ctx.HttpContext.RequestServices.GetRequiredService<CentralDbContext>();
                var ativo = await db.UsuariosPainel.AsNoTracking()
                    .AnyAsync(u => u.Login == login && u.Ativo);
                if (!ativo) ctx.Fail("usuario do painel inativo ou inexistente");
            }
        };
    });
builder.Services.AddAuthorization();

// Rate limiting por IP (defesa contra brute force/credential stuffing). Particiona pelo IP real
// (X-Forwarded-For do proxy do Railway; cai para o RemoteIpAddress).
builder.Services.AddRateLimiter(o =>
{
    o.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    o.AddPolicy("login",      ctx => Limite(IpDe(ctx), 5,   TimeSpan.FromMinutes(1)));
    o.AddPolicy("admin",      ctx => Limite(IpDe(ctx), 10,  TimeSpan.FromMinutes(1)));
    o.AddPolicy("telemetria", ctx => Limite(IpDe(ctx), 120, TimeSpan.FromMinutes(1)));
});

builder.Services.AddResponseCompression();

// Menu VERSÕES: cataloga o GitHub Releases (a Central não hospeda binários).
builder.Services.AddHttpClient("github");
builder.Services.AddMemoryCache();
builder.Services.AddScoped<SigeDash.Central.Servicos.GithubReleases>();

// Integração Superlógica (polling diário → kill-switch automático por CNPJ). No-op se não configurado.
builder.Services.AddHttpClient("superlogica");
builder.Services.AddSingleton<SigeDash.Central.Servicos.SuperlogicaClient>();
builder.Services.AddHostedService<SigeDash.Central.Servicos.SuperlogicaSyncHostedService>();

// Retenção/expurgo (LGPD) do histórico de heartbeats.
builder.Services.AddHostedService<SigeDash.Central.Servicos.RetencaoHostedService>();

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

// Cabeçalhos de segurança (defesa-em-profundidade no painel público).
app.Use(async (ctx, next) =>
{
    var h = ctx.Response.Headers;
    h["X-Content-Type-Options"] = "nosniff";
    h["X-Frame-Options"] = "DENY";
    h["Referrer-Policy"] = "no-referrer";
    h["Content-Security-Policy"] =
        "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " +
        "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; object-src 'none'";
    if (ctx.Request.IsHttps) h["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains";
    await next();
});

app.UseResponseCompression();
app.UseDefaultFiles();
app.UseStaticFiles();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new { ok = true, servico = "sigedash-central" }));
app.MapTelemetria(app.Configuration);
app.MapPainel(app.Configuration);
app.MapUsuariosPainel();
app.MapVersoes();
app.MapAdminCentral(app.Configuration);

app.MapFallbackToFile("index.html");

app.Run();


// ── Helpers ─────────────────────────────────────────────────────────────────
static RateLimitPartition<string> Limite(string chave, int limite, TimeSpan janela)
    => RateLimitPartition.GetFixedWindowLimiter(chave, _ => new FixedWindowRateLimiterOptions
    {
        PermitLimit = limite, Window = janela, QueueLimit = 0
    });

static string IpDe(HttpContext ctx)
{
    var xff = ctx.Request.Headers["X-Forwarded-For"].ToString();
    if (!string.IsNullOrWhiteSpace(xff)) return xff.Split(',')[0].Trim();
    return ctx.Connection.RemoteIpAddress?.ToString() ?? "desconhecido";
}

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
        db.UsuariosPainel.Add(new UsuarioPainel
        {
            Login = login, SenhaHash = Auth.HashSenha(senha),
            Papel = PapelPainel.Admin, Ativo = true, CriadoPor = "sistema"
        });
        db.SaveChanges();
        logger.LogInformation("Usuário do painel '{login}' criado (admin).", login);
    }
    else
    {
        // Mantém a senha em dia com a variável de ambiente (permite reset trocando a env) e
        // garante que o admin semeado nunca fique sem poder de gestão nem desativado.
        existente.SenhaHash = Auth.HashSenha(senha);
        existente.Papel = PapelPainel.Admin;
        existente.Ativo = true;
        db.SaveChanges();
    }
}
