namespace SigeDash.Central.Modelos;

/// <summary>Um cliente/instalação do SigeDash na frota. Cada um tem uma ChaveTelemetria própria.</summary>
public class ClienteCentral
{
    public int Id { get; set; }
    public string Nome { get; set; } = "";
    public string? Cnpj { get; set; }
    public string ChaveTelemetria { get; set; } = "";
    public int LimiteDispositivos { get; set; }        // limite de dispositivos (seats) do cliente
    // Quando true, a CENTRAL é a fonte do limite (liberação de mais acessos pela SistemasBr): o heartbeat
    // responde o limite ao cliente e NÃO espelha mais o valor reportado por ele. Default false = espelha
    // o limite do install (comportamento antigo), até a SistemasBr definir pelo painel.
    public bool LimiteGerenciadoCentral { get; set; }
    public DateTime? LimiteAtualizadoEm { get; set; }
    public string? LimitePor { get; set; }
    public bool Ativo { get; set; } = true;            // registro válido (aceita telemetria) — NÃO é a assinatura
    public DateTime CriadoEm { get; set; } = DateTime.UtcNow;
    public string? Observacao { get; set; }

    // ── Assinatura (kill-switch por PULL: o cliente lê o estado no heartbeat) ──
    public string Estado { get; set; } = EstadoAssinatura.Ativo;   // ativo | trial | suspenso | cancelado
    public DateTime? ExpiraEm { get; set; }                        // validade do trial/assinatura (informativo)
    public string? MotivoBloqueio { get; set; }                    // mensagem opcional exibida ao cliente
    public DateTime? EstadoAtualizadoEm { get; set; }
    public string? EstadoPor { get; set; }
    public DateTime? SincronizadoSuperlogicaEm { get; set; }   // última verificação no Superlógica (polling)

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

/// <summary>Curadoria do menu VERSÕES: marca quais releases do GitHub estão liberadas para o
/// suporte/implementação ver e baixar. A Central NÃO hospeda binários — cataloga o GitHub Releases
/// (onde os pacotes já estão assinados) e guarda apenas o estado de liberação por tag.</summary>
public class VersaoLiberada
{
    public string Tag { get; set; } = "";              // ex.: v1.0.42 (chave)
    public bool Liberada { get; set; }
    public DateTime AtualizadoEm { get; set; } = DateTime.UtcNow;
    public string? AtualizadoPor { get; set; }
}

/// <summary>Relatório de uma tentativa de instalação (ou diagnóstico) enviado pelo servidor do cliente.
/// Permite ao suporte ver o que falhou sem acessar o servidor. Chega mesmo quando o cliente ainda
/// não está registrado (falha antes do registro) — por isso guarda Nome/Cnpj próprios.
/// O script mascara senhas/chaves/tokens antes de enviar.</summary>
public class RelatorioInstalacao
{
    public long Id { get; set; }
    public DateTime RecebidoEm { get; set; } = DateTime.UtcNow;
    public int? ClienteId { get; set; }                 // casado por CNPJ/Nome quando o cliente já existe
    public string Tipo { get; set; } = "instalacao";    // instalacao | diagnostico
    public string Nome { get; set; } = "";
    public string? Cnpj { get; set; }
    public string? Versao { get; set; }
    public string? Os { get; set; }
    public string? Maquina { get; set; }
    public string Status { get; set; } = "";            // sucesso | sucesso_avisos | falha | bloqueado
    public string? Etapa { get; set; }                  // ex.: "PASSO 1 - PostgreSQL 16"
    public string? Mensagem { get; set; }
    public string? Avisos { get; set; }                 // linhas de AVISO, uma por linha
    public string? Url { get; set; }
    public int? DuracaoSeg { get; set; }
    public int Bloqueios { get; set; }                  // da pré-verificação
    public string? Verificacoes { get; set; }           // JSON da pré-verificação
    public string? Log { get; set; }                    // log mascarado (cauda)
    public string? Ip { get; set; }
}

public record RelatorioInstalacaoDto(
    string? Tipo, string? Nome, string? Cnpj, string? Versao, string? Os, string? Maquina,
    string? Status, string? Etapa, string? Mensagem, List<string>? Avisos, int? DuracaoSeg,
    string? Url, string? Verificacoes, string? Log);

/// <summary>Estados possíveis da assinatura de um cliente.</summary>
public static class EstadoAssinatura
{
    public const string Ativo = "ativo";
    public const string Trial = "trial";
    public const string Suspenso = "suspenso";
    public const string Cancelado = "cancelado";

    public static readonly string[] Todos = { Ativo, Trial, Suspenso, Cancelado };

    /// <summary>Estados em que o cliente deve se auto-bloquear (kill-switch).</summary>
    public static bool Bloqueia(string estado) => estado is Suspenso or Cancelado;
}

/// <summary>Trilha de auditoria das ações do painel (quem fez o quê e quando).</summary>
public class LogAuditoria
{
    public long Id { get; set; }
    public DateTime Ts { get; set; } = DateTime.UtcNow;
    public string Usuario { get; set; } = "";
    public string Acao { get; set; } = "";
    public int? ClienteId { get; set; }
    public string? Detalhe { get; set; }
}

/// <summary>Usuário do painel interno da SistemasBr.</summary>
public class UsuarioPainel
{
    public int Id { get; set; }
    public string Login { get; set; } = "";
    public string SenhaHash { get; set; } = "";
    public DateTime? UltimoLoginEm { get; set; }

    // Papel: admin (gerencia a equipe) ou operador (usa a Central, mas não gerencia usuários).
    public string Papel { get; set; } = PapelPainel.Operador;
    public bool Ativo { get; set; } = true;                 // desativado = não consegue logar
    public DateTime CriadoEm { get; set; } = DateTime.UtcNow;
    public string? CriadoPor { get; set; }

    // Lockout por tentativas (defesa contra brute force, além do rate limit por IP).
    public int TentativasFalhas { get; set; }
    public DateTime? BloqueadoAte { get; set; }
}

/// <summary>Papéis do usuário do painel.</summary>
public static class PapelPainel
{
    public const string Admin = "admin";        // gerencia a equipe (criar/remover usuários)
    public const string Operador = "operador";  // usa a Central (frota, versões, kill-switch, limite)

    public static readonly string[] Todos = { Admin, Operador };
    public static bool EhAdmin(string? papel) => string.Equals(papel, Admin, StringComparison.OrdinalIgnoreCase);
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
