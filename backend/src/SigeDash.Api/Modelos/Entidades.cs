namespace SigeDash.Api.Modelos;

/// <summary>Cada cliente (empresa que usa o SIGECOM). A chave_api autentica o agente.</summary>
public class Cliente
{
    public int Id { get; set; }
    public string Nome { get; set; } = "";
    public string ChaveApi { get; set; } = "";
    public bool Ativo { get; set; } = true;
    public List<Loja> Lojas { get; set; } = new();
}

/// <summary>Loja/empresa dentro do cliente (mapeia CODIGOEMPRESA do Firebird).</summary>
public class Loja
{
    public int Id { get; set; }
    public int ClienteId { get; set; }
    public int CodigoEmpresa { get; set; }
    public string Nome { get; set; } = "";
}

/// <summary>Usuario do app mobile. Senha em BCrypt (nunca SHA-1 do PlugBot).</summary>
public class UsuarioApp
{
    public int Id { get; set; }
    public int ClienteId { get; set; }
    public string Login { get; set; } = "";
    public string? Email { get; set; }
    public string SenhaHash { get; set; } = "";
    public string? Departamento { get; set; }
}

/// <summary>Snapshot de um indicador recebido do agente. payload_json e o resultado pronto.</summary>
public class Snapshot
{
    public long Id { get; set; }
    public int ClienteId { get; set; }
    public int CodigoEmpresa { get; set; }
    public string IndicadorHandle { get; set; } = "";
    public string PayloadJson { get; set; } = "";
    public DateTime GeradoEm { get; set; }
    public DateTime RecebidoEm { get; set; }
}
