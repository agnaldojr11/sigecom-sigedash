using System.Text.Json.Nodes;
using SigeDash.Api.Modelos;

namespace SigeDash.Api;

/// <summary>
/// Regras de permissao por secao (e sub-permissoes). O "Administrador" do Sigecom
/// (USUARIO.CODIGOTIPO == 1) ve tudo; os demais so veem o que o admin liberar
/// (UsuarioApp.SecoesPermitidas). A trava real e aplicada no /dash: filtra os snapshots
/// por secao e remove campos sensiveis (ex.: custo) quando a sub-permissao nao esta ligada.
/// </summary>
public static class Permissoes
{
    public const int TipoAdministrador = 1;

    // Secoes da navegacao. "resumo" nao tem handle proprio (compoe KPIs das outras).
    public const string Resumo     = "resumo";
    public const string Vendas     = "vendas";
    public const string Estoque    = "estoque";
    public const string Financeiro = "financeiro";

    // Sub-permissoes (dentro de uma secao). Extensivel.
    public const string EstoqueCusto = "estoque_custo"; // ver preco de custo na pesquisa de produtos

    public static readonly string[] Secoes = { Resumo, Vendas, Estoque, Financeiro };
    // Tokens validos aceitos/armazenados (secoes + sub-permissoes)
    public static readonly string[] Validos = { Resumo, Vendas, Estoque, Financeiro, EstoqueCusto };

    public const string HandlePesquisaProduto = "estoque_pesquisa_produto";

    public static bool EhAdmin(UsuarioApp u) => u.CodigoTipo == TipoAdministrador;

    /// <summary>Tokens efetivos do usuario: admin = tudo; senao = os liberados (ou vazio).</summary>
    public static HashSet<string> SecoesEfetivas(UsuarioApp u)
    {
        if (EhAdmin(u)) return new HashSet<string>(Validos);
        return ParseSecoes(u.SecoesPermitidas);
    }

    /// <summary>Normaliza uma lista separada por virgula, aceitando apenas tokens validos.</summary>
    public static HashSet<string> ParseSecoes(string? csv)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrWhiteSpace(csv)) return set;
        foreach (var parte in csv.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            if (Array.Exists(Validos, s => s.Equals(parte, StringComparison.OrdinalIgnoreCase)))
                set.Add(parte.ToLowerInvariant());
        // Sub-permissao so vale se a secao pai estiver ligada
        if (set.Contains(EstoqueCusto) && !set.Contains(Estoque)) set.Remove(EstoqueCusto);
        return set;
    }

    /// <summary>Secao a que um handle de indicador pertence (para filtrar o /dash).</summary>
    public static string SecaoDoHandle(string handle)
    {
        if (handle.StartsWith("vendas_",  StringComparison.OrdinalIgnoreCase)) return Vendas;
        if (handle.StartsWith("estoque_", StringComparison.OrdinalIgnoreCase)) return Estoque;
        if (handle.StartsWith("financeiro_", StringComparison.OrdinalIgnoreCase)) return Financeiro;
        if (handle is "receber_por_cliente" or "saldo_caixas" or "saldo_bancario") return Financeiro;
        return Financeiro; // desconhecido -> trata como sensivel (fail-safe)
    }

    /// <summary>Se o usuario (dadas as secoes efetivas) pode receber o snapshot do handle.</summary>
    public static bool PodeVerHandle(string handle, HashSet<string> secoes)
        => secoes.Contains(SecaoDoHandle(handle));

    /// <summary>
    /// Ajusta o payload de um snapshot conforme as sub-permissoes. Hoje: remove o campo
    /// "custo" da pesquisa de produtos quando o usuario nao tem a permissao estoque_custo.
    /// Retorna o JSON original se nada precisa ser alterado.
    /// </summary>
    public static string AjustarPayload(string handle, string payloadJson, HashSet<string> secoes)
    {
        if (handle != HandlePesquisaProduto || secoes.Contains(EstoqueCusto))
            return payloadJson;

        var node = JsonNode.Parse(payloadJson);
        var dados = node?["dados"]?.AsArray();
        if (dados is null) return payloadJson;
        foreach (var d in dados)
            (d as JsonObject)?.Remove("custo");
        return node!.ToJsonString();
    }
}
