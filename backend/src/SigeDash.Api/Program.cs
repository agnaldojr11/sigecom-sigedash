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
            ValidateLifetime = true
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
    p.AllowAnyHeader().AllowAnyMethod().WithOrigins(allowedOrigins)));

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
