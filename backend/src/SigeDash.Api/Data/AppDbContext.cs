using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Modelos;

namespace SigeDash.Api.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<Cliente> Clientes => Set<Cliente>();
    public DbSet<Loja> Lojas => Set<Loja>();
    public DbSet<UsuarioApp> UsuariosApp => Set<UsuarioApp>();
    public DbSet<Snapshot> Snapshots => Set<Snapshot>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Cliente>().HasIndex(c => c.ChaveApi).IsUnique();
        b.Entity<UsuarioApp>().HasIndex(u => new { u.ClienteId, u.Login }).IsUnique();
        // ultimo snapshot por (cliente, empresa, indicador) e a consulta quente do PWA
        b.Entity<Snapshot>().HasIndex(s => new { s.ClienteId, s.CodigoEmpresa, s.IndicadorHandle, s.GeradoEm });
    }
}
