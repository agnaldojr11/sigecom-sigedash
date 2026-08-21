using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace SigeDash.Central.Data;

/// <summary>
/// Usado APENAS pelo 'dotnet ef' (design-time) para gerar/aplicar migrações sem subir o host da app
/// (evita o fail-fast do Jwt:SecretKey do Program.cs). Em runtime a conexão vem do DATABASE_URL.
/// </summary>
public class CentralDbContextFactory : IDesignTimeDbContextFactory<CentralDbContext>
{
    public CentralDbContext CreateDbContext(string[] args)
    {
        var opt = new DbContextOptionsBuilder<CentralDbContext>()
            .UseNpgsql("Host=localhost;Port=5432;Database=sigedash_central;Username=postgres;Password=postgres")
            .Options;
        return new CentralDbContext(opt);
    }
}
