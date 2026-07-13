using SigeDash.Api.Modelos;

namespace SigeDash.Api;

/// <summary>
/// Regras de permissao por secao. O "Administrador" do Sigecom (USUARIO.CODIGOTIPO == 1)
/// ve tudo; os demais so veem as secoes que o admin liberar (UsuarioApp.SecoesPermitidas).
/// A trava real e aplicada no /dash (filtro de snapshots); o PWA apenas complementa escondendo abas.
/// </summary>
public static class Permissoes
{
    public const int TipoAdministrador = 1;

    // Secoes da navegacao. "resumo" nao tem handle proprio (compoe KPIs das outras).
    public const string Resumo     = "resumo";
    public const string Vendas     = "vendas";
    public const string Estoque    = "estoque";
    public const string Financeiro = "financeiro";

    public static readonly string[] Todas = { Resumo, Vendas, Estoque, Financeiro };

    public static bool EhAdmin(UsuarioApp u) => u.CodigoTipo == TipoAdministrador;

    /// <summary>Secoes efetivas do usuario: admin = todas; senao = as liberadas (ou vazio).</summary>
    public static HashSet<string> SecoesEfetivas(UsuarioApp u)
    {
        if (EhAdmin(u)) return new HashSet<string>(Todas);
        return ParseSecoes(u.SecoesPermitidas);
    }

    /// <summary>Normaliza uma lista separada por virgula, aceitando apenas secoes validas.</summary>
    public static HashSet<string> ParseSecoes(string? csv)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(csv)) return set;
        foreach (var parte in csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            if (Array.Exists(Todas, s => s.Equals(parte, StringComparison.OrdinalIgnoreCase)))
                set.Add(parte.ToLowerInvariant());
        return set;
    }

    /// <summary>Secao a que um handle de indicador pertence (para filtrar o /dash).</summary>
    public static string SecaoDoHandle(string handle)
    {
        if (handle.StartsWith("vendas_",  StringComparison.OrdinalIgnoreCase)) return Vendas;
        if (handle.StartsWith("estoque_", StringComparison.OrdinalIgnoreCase)) return Estoque;
        if (handle.StartsWith("financeiro_", StringComparison.OrdinalIgnoreCase)) return Financeiro;
        // Financeiros sem o prefixo padrao:
        if (handle is "receber_por_cliente" or "saldo_caixas" or "saldo_bancario") return Financeiro;
        return Financeiro; // desconhecido -> trata como sensivel (fail-safe)
    }

    /// <summary>Se o usuario (dadas as secoes efetivas) pode receber o snapshot do handle.</summary>
    public static bool PodeVerHandle(string handle, HashSet<string> secoes)
        => secoes.Contains(SecaoDoHandle(handle));
}
