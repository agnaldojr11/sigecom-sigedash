using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Modelos;

namespace SigeDash.Central.Data;

public class CentralDbContext : DbContext
{
    public CentralDbContext(DbContextOptions<CentralDbContext> options) : base(options) { }

    public DbSet<ClienteCentral> Clientes => Set<ClienteCentral>();
    public DbSet<Heartbeat> Heartbeats => Set<Heartbeat>();
    public DbSet<HeartbeatHistorico> HeartbeatHistorico => Set<HeartbeatHistorico>();
    public DbSet<IndicadorSaude> IndicadoresSaude => Set<IndicadorSaude>();
    public DbSet<UsuarioPainel> UsuariosPainel => Set<UsuarioPainel>();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<ClienteCentral>(e =>
        {
            e.HasIndex(x => x.ChaveTelemetria).IsUnique();
            e.HasIndex(x => x.Nome);
            e.HasOne(x => x.Heartbeat).WithOne().HasForeignKey<Heartbeat>(h => h.ClienteId).OnDelete(DeleteBehavior.Cascade);
            e.HasMany(x => x.Indicadores).WithOne().HasForeignKey(i => i.ClienteId).OnDelete(DeleteBehavior.Cascade);
        });

        b.Entity<Heartbeat>(e => e.HasIndex(x => x.ClienteId).IsUnique());

        b.Entity<IndicadorSaude>(e => e.HasIndex(x => new { x.ClienteId, x.Handle }).IsUnique());

        b.Entity<HeartbeatHistorico>(e => e.HasIndex(x => new { x.ClienteId, x.Ts }));

        b.Entity<UsuarioPainel>(e => e.HasIndex(x => x.Login).IsUnique());
    }
}
