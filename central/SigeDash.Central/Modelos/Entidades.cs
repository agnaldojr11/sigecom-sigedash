namespace SigeDash.Central.Modelos;

/// <summary>Um cliente/instalação do SigeDash na frota. Cada um tem uma ChaveTelemetria própria.</summary>
public class ClienteCentral
{
    public int Id { get; set; }
    public string Nome { get; set; } = "";
    public string? Cnpj { get; set; }
    public string ChaveTelemetria { get; set; } = "";
    public int LimiteDispositivos { get; set; }        // espelho do plano (informativo)
    public bool Ativo { get; set; } = true;
    public DateTime CriadoEm { get; set; } = DateTime.UtcNow;
    public string? Observacao { get; set; }

    public Heartbeat? Heartbeat { get; set; }          // estado atual (1:1)
    public List<IndicadorSaude> Indicadores { get; set; } = new();
}

/// <summary>Estado mais recente do cliente (upsert a cada heartbeat).</summary>
public class Heartbeat
{
    public int Id { get; set; }
    public int ClienteId { get; set; }
    public DateTime RecebidoEm { get; set; }
    public string? Versao { get; set; }
    public long UptimeSeg { get; set; }
    public int UsuariosAtivos { get; set; }
    public int LimiteDispositivos { get; set; }
    public string? Os { get; set; }
    public string? StatusBackend { get; set; }         // ok | degradado
    public string? StatusPg { get; set; }              // ok | erro
    public string? Ip { get; set; }
}

/// <summary>Série temporal enxuta (para gráfico de uso/uptime). Retenção controlada por limpeza.</summary>
public class HeartbeatHistorico
{
    public long Id { get; set; }
    public int ClienteId { get; set; }
    public DateTime Ts { get; set; }
    public string? Versao { get; set; }
    public int UsuariosAtivos { get; set; }
}

/// <summary>Saúde de cada indicador coletado pelo agente do cliente.</summary>
public class IndicadorSaude
{
    public int Id { get; set; }
    public int ClienteId { get; set; }
    public string Handle { get; set; } = "";
    public DateTime? UltimoSucesso { get; set; }
    public DateTime? UltimoErro { get; set; }
    public string Status { get; set; } = "";           // ok | erro | atrasado
    public string? Mensagem { get; set; }
    public DateTime AtualizadoEm { get; set; }
}

/// <summary>Usuário do painel interno da SistemasBr.</summary>
public class UsuarioPainel
{
    public int Id { get; set; }
    public string Login { get; set; } = "";
    public string SenhaHash { get; set; } = "";
    public DateTime? UltimoLoginEm { get; set; }

    // Lockout por tentativas (defesa contra brute force, além do rate limit por IP).
    public int TentativasFalhas { get; set; }
    public DateTime? BloqueadoAte { get; set; }
}

// ── DTOs de telemetria (payload que o cliente envia) ────────────────────────
public record HeartbeatDto(
    string? Versao,
    long UptimeSeg,
    int UsuariosAtivos,
    int LimiteDispositivos,
    string? Os,
    string? StatusBackend,
    string? StatusPg,
    List<IndicadorDto>? Indicadores);

public record IndicadorDto(
    string Handle,
    string Status,
    DateTime? UltimoSucesso,
    DateTime? UltimoErro,
    string? Mensagem);
