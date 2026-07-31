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

/// <summary>Usuario do app — NATIVO do SigeDash (nao vem mais do SIGECOM). Criado e gerenciado
/// pelo ADM da empresa. Senha em BCrypt. Suporta 2FA (TOTP), bloqueio por tentativas e auditoria.</summary>
public class UsuarioApp
{
    public int Id { get; set; }
    public int ClienteId { get; set; }
    public string Login { get; set; } = "";

    /// <summary>Hash BCrypt da senha.</summary>
    public string SenhaHash { get; set; } = "";

    /// <summary>Nome para exibicao (opcional).</summary>
    public string? NomeExibicao { get; set; }

    /// <summary>Administrador da empresa: acesso total + gestao de usuarios e permissoes.</summary>
    public bool EhAdmin { get; set; }

    /// <summary>Usuario ativo. Inativo nao consegue logar.</summary>
    public bool Ativo { get; set; } = true;

    /// <summary>Obriga trocar a senha no proximo login (primeiro acesso / senha resetada pelo admin).</summary>
    public bool PrecisaTrocarSenha { get; set; }

    /// <summary>Secoes liberadas para nao-admins, separadas por virgula (ex.: "estoque,vendas").
    /// null = nada liberado (usuario aguarda configuracao do admin). Ignorado para admins (veem tudo).</summary>
    public string? SecoesPermitidas { get; set; }

    /// <summary>Identificador da sessao ativa (sessao unica). Cada login gera um novo valor;
    /// o token carrega o mesmo em uma claim. Se nao bater, a sessao foi substituida (login em outro lugar).</summary>
    public string? SessaoToken { get; set; }

    // --- Anti-forca-bruta ---
    /// <summary>Tentativas de login malsucedidas consecutivas.</summary>
    public int TentativasFalhas { get; set; }
    /// <summary>Se preenchido e no futuro, o login esta bloqueado ate esse instante.</summary>
    public DateTime? BloqueadoAte { get; set; }

    // --- 2FA (TOTP) ---
    /// <summary>Segredo TOTP em base32 (null = 2FA nao configurado).</summary>
    public string? TotpSecret { get; set; }
    /// <summary>2FA ativado e confirmado (exige codigo no login).</summary>
    public bool TotpAtivado { get; set; }

    // --- Auditoria ---
    public DateTime CriadoEm { get; set; }
    public DateTime? AtualizadoEm { get; set; }
    public DateTime? UltimoLoginEm { get; set; }
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
