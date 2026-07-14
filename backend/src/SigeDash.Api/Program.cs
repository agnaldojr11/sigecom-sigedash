using System.IO.Compression;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.ResponseCompression;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using SigeDash.Api.Data;
using SigeDash.Api.Endpoints;

// AppContext.BaseDirectory = diretório do .exe (funciona como serviço Windows onde CWD é System32)
var appDir      = AppContext.BaseDirectory;
var wwwrootPath = Path.Combine(appDir, "wwwroot");
Directory.CreateDirectory(wwwrootPath);

// Dev: serve da pasta pwa/ (fonte) | Produção: usa wwwroot/ (copiado no publish)
var pwaDev  = Path.GetFullPath(Path.Combine(appDir, "../../../pwa"));
var webRoot = Directory.Exists(pwaDev) ? pwaDev : wwwrootPath;

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args        = args,
    WebRootPath = webRoot
});

// Carrega credenciais locais reais (gitignored) — sobrescreve appsettings.Development.json
builder.Configuration.AddJsonFile(
    $"appsettings.{builder.Environment.EnvironmentName}.local.json",
    optional: true, reloadOnChange: true);

builder.Services.AddDbContext<AppDbContext>(o =>
    o.UseNpgsql(builder.Configuration.GetConnectionString("Postgres")));

// Falha cedo se a chave de assinatura do JWT estiver ausente ou fraca (< 32 bytes = < 256 bits para HS256)
var jwtSecret = builder.Configuration["Jwt:SecretKey"];
if (string.IsNullOrWhiteSpace(jwtSecret) || Encoding.UTF8.GetByteCount(jwtSecret) < 32)
    throw new InvalidOperationException("Jwt:SecretKey ausente ou fraca (minimo 32 bytes). Gere uma chave forte (CSPRNG).");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opt =>
    {
        var cfg = builder.Configuration;
        opt.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true, ValidIssuer = cfg["Jwt:Issuer"],
            ValidateAudience = true, ValidAudience = cfg["Jwt:Audience"],
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(cfg["Jwt:SecretKey"]!)),
            ValidateLifetime = true,
            ValidAlgorithms = new[] { SecurityAlgorithms.HmacSha256 },  // fixa HMAC (defesa contra alg confusion/none)
            ClockSkew = TimeSpan.FromSeconds(30)
        };
        // Sessao unica: o sid do token precisa bater com o sid atual do usuario no banco.
        // Se nao bater (login em outro lugar), rejeita com header X-Sessao=encerrada.
        opt.Events = new JwtBearerEvents
        {
            OnTokenValidated = async ctx =>
            {
                var db  = ctx.HttpContext.RequestServices.GetRequiredService<AppDbContext>();
                var uid = ctx.Principal?.FindFirst("usuario_id")?.Value;
                var sid = ctx.Principal?.FindFirst("sid")?.Value;
                if (!int.TryParse(uid, out var usuarioId)) { ctx.Fail("token invalido"); return; }
                var atual = await db.UsuariosApp
                    .Where(u => u.Id == usuarioId).Select(u => u.SessaoToken).FirstOrDefaultAsync();
                if (string.IsNullOrEmpty(sid) || sid != atual)
                {
                    ctx.Response.Headers["X-Sessao"] = "encerrada";
                    ctx.Fail("sessao encerrada");
                }
            }
        };
    });
builder.Services.AddAuthorization();
builder.Services.AddHttpClient("claude");

// Compressao de resposta (gzip/brotli). O /dash pode trafegar a lista completa de
// produtos (milhares de linhas); JSON repetitivo comprime para uma fracao do tamanho.
// EnableForHttps: o backend pode atender direto (sem o tunnel comprimir na borda).
builder.Services.AddResponseCompression(o =>
{
    o.EnableForHttps = true;
    o.Providers.Add<BrotliCompressionProvider>();
    o.Providers.Add<GzipCompressionProvider>();
    o.MimeTypes = ResponseCompressionDefaults.MimeTypes.Concat(new[] { "application/json" });
});
builder.Services.Configure<BrotliCompressionProviderOptions>(o => o.Level = CompressionLevel.Fastest);
builder.Services.Configure<GzipCompressionProviderOptions>(o => o.Level = CompressionLevel.Fastest);

// CORS configurável via appsettings (apenas necessário em dev; produção usa mesmo origin)
var allowedOrigins = builder.Configuration.GetSection("AllowedOrigins").Get<string[]>()
                     ?? ["http://localhost:5000", "http://localhost:8080"];
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.AllowAnyHeader().AllowAnyMethod().WithOrigins(allowedOrigins).WithExposedHeaders("X-Sessao")));

// Rate limiting: /auth/login — máx 5 tentativas por IP por minuto
builder.Services.AddRateLimiter(opt =>
{
    opt.AddPolicy("login", ctx =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: ctx.Connection.RemoteIpAddress?.ToString() ?? "anon",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit          = 5,
                Window               = TimeSpan.FromMinutes(1),
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                QueueLimit           = 0
            }));
    // /ingest — por IP: permite o agente (dezenas de POST por ciclo) e limita brute force da ChaveApi
    opt.AddPolicy("ingest", ctx =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: ctx.Connection.RemoteIpAddress?.ToString() ?? "anon",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120, Window = TimeSpan.FromMinutes(1),
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst, QueueLimit = 0
            }));
    // /ia — por IP: uso humano de chat; corta abuso/custo
    opt.AddPolicy("ia", ctx =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: ctx.Connection.RemoteIpAddress?.ToString() ?? "anon",
            factory: _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 20, Window = TimeSpan.FromMinutes(1),
                QueueProcessingOrder = QueueProcessingOrder.OldestFirst, QueueLimit = 0
            }));
    opt.RejectionStatusCode = 429;
});

// Suporte a execução como Windows Service (no-op quando rodando normalmente)
builder.Host.UseWindowsService();

var app = builder.Build();

// Aplica migrations automaticamente (dev + produção)
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
    if (app.Environment.IsDevelopment())
        SeedData.Seed(db);
}

// Compressao deve vir cedo no pipeline (comprime estaticos e respostas de API)
app.UseResponseCompression();

// Headers de seguranca em todas as respostas. A CSP sem 'unsafe-inline' em script-src bloqueia
// handlers inline (ex.: onerror=) — defesa em profundidade contra XSS. Chart.js vem do cdnjs.
app.Use(async (ctx, next) =>
{
    var h = ctx.Response.Headers;
    h["X-Content-Type-Options"] = "nosniff";
    h["X-Frame-Options"]        = "DENY";
    h["Referrer-Policy"]        = "no-referrer";
    h["Permissions-Policy"]     = "geolocation=(), microphone=(), camera=(), payment=()";
    h["Content-Security-Policy"] =
        "default-src 'self'; " +
        // cdnjs = Chart.js; static.cloudflareinsights.com = beacon de Web Analytics injetado pela Cloudflare
        "script-src 'self' https://cdnjs.cloudflare.com https://static.cloudflareinsights.com; " +
        "style-src 'self' 'unsafe-inline'; " +
        "img-src 'self' data:; font-src 'self'; " +
        "connect-src 'self' https://cloudflareinsights.com; " +   // POST do beacon (RUM)
        "object-src 'none'; base-uri 'self'; frame-ancestors 'none'; form-action 'self'";
    if (ctx.Request.IsHttps || ctx.Request.Headers["X-Forwarded-Proto"] == "https")
        h["Strict-Transport-Security"] = "max-age=31536000";
    await next();
});

// Serve o PWA (wwwroot/): index.html, css, js, service worker, ícones
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapIngest();
app.MapAuth(app.Configuration);
app.MapDashboards();
app.MapIa();
app.MapAdmin(app.Configuration);
app.MapPermissoes();

// Fallback para SPA — todas as rotas não-API servem index.html
app.MapFallbackToFile("index.html");

app.Run();
