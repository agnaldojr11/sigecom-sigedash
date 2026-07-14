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

/// <summary>Usuario do app. Login e SenhaApp sincronizados da tabela USUARIO do Firebird pelo agente.</summary>
public class UsuarioApp
{
    public int Id { get; set; }
    public int ClienteId { get; set; }
    public string Login { get; set; } = "";
    public string SenhaApp { get; set; } = ""; // SHA-1 hex do campo SENHA_APP do Sigecom

    /// <summary>USUARIO.CODIGOTIPO do Sigecom. 1 = Administrador (acesso total + gestao de permissoes).</summary>
    public int CodigoTipo { get; set; }

    /// <summary>Secoes liberadas para nao-admins, separadas por virgula (ex.: "estoque,vendas").
    /// null = nada liberado (usuario aguarda configuracao do admin). Ignorado para admins (veem tudo).</summary>
    public string? SecoesPermitidas { get; set; }

    /// <summary>Identificador da sessao ativa (sessao unica). Cada login gera um novo valor;
    /// o token carrega o mesmo em uma claim. Se nao bater, a sessao foi substituida (login em outro lugar).</summary>
    public string? SessaoToken { get; set; }
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
