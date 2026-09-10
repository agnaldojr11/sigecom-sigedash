using System.Text.Json;

namespace SigeDash.Api.Servicos;

/// <summary>
/// Estado local da assinatura do cliente (kill-switch). É alimentado pela RESPOSTA do heartbeat
/// (TelemetriaHostedService) e consultado no login e no /dash. Persistido em arquivo para valer já
/// no boot (antes do 1º heartbeat).
///
/// FAIL-OPEN / com carência: só bloqueia por COMANDO EXPLÍCITO da Central ("bloqueado": true).
/// Perda de contato com a Central NÃO bloqueia — mantém o último estado conhecido (um cliente nunca
/// contatado, ou sem telemetria, fica liberado). Assim uma queda da Central/internet não derruba
/// clientes legítimos; e um bloqueio já comandado persiste mesmo offline até a reativação chegar.
/// </summary>
public class EstadoAssinaturaService
{
    private readonly string _arquivo;
    private readonly ILogger<EstadoAssinaturaService> _log;
    private readonly object _lock = new();

    public bool Bloqueado { get; private set; }
    public string Mensagem { get; private set; } = "Assinatura suspensa. Entre em contato com a SistemasBr.";
    public DateTime? AtualizadoEm { get; private set; }

    public EstadoAssinaturaService(ILogger<EstadoAssinaturaService> log)
    {
        _log = log;
        _arquivo = Path.Combine(AppContext.BaseDirectory, "estado-assinatura.json");
        Carregar();
    }

    private sealed record Persistido(bool Bloqueado, string Mensagem, DateTime AtualizadoEm);

    private void Carregar()
    {
        try
        {
            if (!File.Exists(_arquivo)) return;
            var p = JsonSerializer.Deserialize<Persistido>(File.ReadAllText(_arquivo));
            if (p is not null)
            {
                Bloqueado = p.Bloqueado;
                if (!string.IsNullOrWhiteSpace(p.Mensagem)) Mensagem = p.Mensagem;
                AtualizadoEm = p.AtualizadoEm;
            }
        }
        catch (Exception ex) { _log.LogWarning("Falha ao carregar estado de assinatura: {m}", ex.Message); }
    }

    /// <summary>Aplica o estado vindo da Central (na resposta do heartbeat). Só grava em disco quando muda.</summary>
    public void Atualizar(bool bloqueado, string? mensagem)
    {
        lock (_lock)
        {
            var msg = string.IsNullOrWhiteSpace(mensagem) ? Mensagem : mensagem!.Trim();
            AtualizadoEm = DateTime.UtcNow;
            if (bloqueado == Bloqueado && msg == Mensagem) return;   // sem mudança → não regrava

            Bloqueado = bloqueado;
            Mensagem = msg;
            try { File.WriteAllText(_arquivo, JsonSerializer.Serialize(new Persistido(Bloqueado, Mensagem, AtualizadoEm.Value))); }
            catch (Exception ex) { _log.LogWarning("Falha ao salvar estado de assinatura: {m}", ex.Message); }
            _log.LogInformation("Estado de assinatura mudou: bloqueado={b}", bloqueado);
        }
    }
}
