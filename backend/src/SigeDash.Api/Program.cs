using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using SigeDash.Api.Data;
using SigeDash.Api.Endpoints;

// wwwroot/ deve existir antes do CreateBuilder (o StaticWebAssets manifest aponta para ela)
var wwwrootPath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot");
Directory.CreateDirectory(wwwrootPath);

// Dev: serve da pasta pwa/ (fonte) | Produção: usa wwwroot/ (copiado no publish)
var pwaDev  = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "../../../pwa"));
var webRoot = Directory.Exists(pwaDev) ? pwaDev : wwwrootPath;

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    Args        = args,
    WebRootPath = webRoot
});

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

// CORS configurável via appsettings (apenas necessário em dev; produção usa mesmo origin)
var allowedOrigins = builder.Configuration.GetSection("AllowedOrigins").Get<string[]>()
                     ?? ["http://localhost:5000", "http://localhost:8080"];
builder.Services.AddCors(o => o.AddDefaultPolicy(p =>
    p.AllowAnyHeader().AllowAnyMethod().WithOrigins(allowedOrigins)));

var app = builder.Build();

// Aplica migrations automaticamente (dev + produção)
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
    if (app.Environment.IsDevelopment())
        SeedData.Seed(db);
}

// Serve o PWA (wwwroot/): index.html, css, js, service worker, ícones
app.UseDefaultFiles();
app.UseStaticFiles();

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

app.MapIngest();
app.MapAuth(app.Configuration);
app.MapDashboards();
app.MapIa();

// Fallback para SPA — todas as rotas não-API servem index.html
app.MapFallbackToFile("index.html");

app.Run();
