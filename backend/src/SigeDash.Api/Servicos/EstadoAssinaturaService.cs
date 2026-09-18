using System.Text.Json;

namespace SigeDash.Api.Servicos;

/// <summary>
/// Estado que o cliente recebe da SigeDash Central pela RESPOSTA do heartbeat, persistido em arquivo
/// (vale já no boot). Guarda: (a) o kill-switch da assinatura (bloqueado/mensagem) e (b) o aviso de
/// mudança de limite de dispositivos (para o app avisar o admin).
///
/// FAIL-OPEN: só bloqueia por COMANDO EXPLÍCITO da Central; perda de contato não bloqueia.
/// </summary>
public class EstadoAssinaturaService
{
    private readonly string _arquivo;
    private readonly ILogger<EstadoAssinaturaService> _log;
    private readonly object _lock = new();

    public bool Bloqueado { get; private set; }
    public string Mensagem { get; private set; } = "Assinatura suspensa. Entre em contato com a SistemasBr.";
    public DateTime? AtualizadoEm { get; private set; }

    // Limite de dispositivos definido pela Central — para o app avisar o admin quando muda.
    public int LimiteValor { get; private set; }
    public DateTime? LimiteAtualizadoEm { get; private set; }

    public EstadoAssinaturaService(ILogger<EstadoAssinaturaService> log)
    {
        _log = log;
        _arquivo = Path.Combine(AppContext.BaseDirectory, "estado-assinatura.json");
        Carregar();
    }

    private sealed class Persistido
    {
        public bool Bloqueado { get; set; }
        public string Mensagem { get; set; } = "";
        public DateTime? AtualizadoEm { get; set; }
        public int LimiteValor { get; set; }
        public DateTime? LimiteAtualizadoEm { get; set; }
    }

    private void Carregar()
    {
        try
        {
            if (!File.Exists(_arquivo)) return;
            var p = JsonSerializer.Deserialize<Persistido>(File.ReadAllText(_arquivo));
            if (p is null) return;
            Bloqueado = p.Bloqueado;
            if (!string.IsNullOrWhiteSpace(p.Mensagem)) Mensagem = p.Mensagem;
            AtualizadoEm = p.AtualizadoEm;
            LimiteValor = p.LimiteValor;
            LimiteAtualizadoEm = p.LimiteAtualizadoEm;
        }
        catch (Exception ex) { _log.LogWarning("Falha ao carregar estado de assinatura: {m}", ex.Message); }
    }

    private void Salvar()
    {
        try
        {
            var p = new Persistido
            {
                Bloqueado = Bloqueado, Mensagem = Mensagem, AtualizadoEm = AtualizadoEm,
                LimiteValor = LimiteValor, LimiteAtualizadoEm = LimiteAtualizadoEm
            };
            File.WriteAllText(_arquivo, JsonSerializer.Serialize(p));
        }
        catch (Exception ex) { _log.LogWarning("Falha ao salvar estado de assinatura: {m}", ex.Message); }
    }

    /// <summary>Aplica o estado do kill-switch vindo do heartbeat. Só grava em disco quando muda.</summary>
    public void Atualizar(bool bloqueado, string? mensagem)
    {
        lock (_lock)
        {
            var msg = string.IsNullOrWhiteSpace(mensagem) ? Mensagem : mensagem!.Trim();
            AtualizadoEm = DateTime.UtcNow;
            if (bloqueado == Bloqueado && msg == Mensagem) return;
            Bloqueado = bloqueado;
            Mensagem = msg;
            Salvar();
            _log.LogInformation("Estado de assinatura mudou: bloqueado={b}", bloqueado);
        }
    }

    /// <summary>Registra o novo limite definido pela Central (para o app avisar o admin).</summary>
    public void RegistrarLimite(int valor, DateTime atualizadoEm)
    {
        lock (_lock)
        {
            LimiteValor = valor;
            LimiteAtualizadoEm = atualizadoEm;
            Salvar();
        }
    }
}
