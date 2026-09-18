using System.Text.Json;

namespace SigeDash.Central.Servicos;

/// <summary>Resultado enxuto da consulta ao Superlógica por CNPJ (minimização — só flags de estado).</summary>
public record StatusSuperlogica(bool Encontrado, bool TemItemSigedash, bool EmDia);

/// <summary>
/// Consulta a API de Assinaturas do Superlógica POR CNPJ (nunca baixa a base toda — minimização/LGPD).
/// Lê apenas o necessário para o kill-switch: o cliente tem o Item Adicional "SigeDash" ativo? está em dia?
/// Autenticação por app_token + access_token (segredos → env do Railway). No-op se não configurado.
///
/// ⚠️ A doc detalhada do Superlógica está atrás de login: os NOMES exatos dos campos (item adicional e
/// inadimplência) e o filtro por documento precisam ser confirmados com uma resposta real — o parsing
/// está isolado em Interpretar() para ajuste rápido. Endpoints conhecidos: contratos_ativos/pendentes,
/// clientes, cobrancas, produtos_servicos.
/// </summary>
public sealed class SuperlogicaClient
{
    private readonly IHttpClientFactory _http;
    private readonly ILogger<SuperlogicaClient> _log;
    private readonly string _appToken;
    private readonly string _accessToken;
    private readonly string _urlBase;
    private readonly string _itemAdicional;

    public SuperlogicaClient(IHttpClientFactory http, IConfiguration cfg, ILogger<SuperlogicaClient> log)
    {
        _http = http; _log = log;
        _appToken      = cfg["Superlogica:AppToken"] ?? "";
        _accessToken   = cfg["Superlogica:AccessToken"] ?? "";
        _urlBase       = (cfg["Superlogica:UrlBase"] ?? "https://api.superlogica.net/v2").TrimEnd('/');
        _itemAdicional = cfg["Superlogica:ItemAdicional"] ?? "SigeDash";
    }

    public bool Configurado => !string.IsNullOrWhiteSpace(_appToken) && !string.IsNullOrWhiteSpace(_accessToken);

    /// <summary>Consulta os contratos do cliente (por CNPJ) e devolve os flags. null = erro/não conclui.</summary>
    public async Task<StatusSuperlogica?> ConsultarPorCnpjAsync(string cnpj, CancellationToken ct)
    {
        if (!Configurado || string.IsNullOrWhiteSpace(cnpj)) return null;

        // Consulta SÓ os contratos deste CNPJ (pesquisa direcionada — não lista a base inteira).
        // ⚠️ confirmar o parâmetro de filtro por documento na doc (ex.: pesquisa=/ ID_CLIENTE_SAC=).
        var url = $"{_urlBase}/contratos?comContratosDosProdutos=1&pesquisa={Uri.EscapeDataString(cnpj)}";
        var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.Add("app_token", _appToken);
        req.Headers.Add("access_token", _accessToken);
        req.Headers.Add("Accept", "application/json");

        try
        {
            using var cli = _http.CreateClient("superlogica");
            cli.Timeout = TimeSpan.FromSeconds(30);
            using var res = await cli.SendAsync(req, ct);
            if (!res.IsSuccessStatusCode)
            {
                _log.LogWarning("Superlógica: HTTP {code} ao consultar CNPJ.", (int)res.StatusCode);
                return null;
            }
            var json = await res.Content.ReadAsStringAsync(ct);
            return Interpretar(json);
        }
        catch (Exception ex)
        {
            _log.LogWarning("Superlógica: falha ao consultar CNPJ: {m}", ex.Message);
            return null;
        }
    }

    /// <summary>
    /// Extrai os flags da resposta. ISOLADO de propósito: quando tivermos um exemplo real de resposta,
    /// ajustamos SÓ este método (nomes de campos do item adicional e da inadimplência).
    /// Heurística atual (a validar): procura um contrato ativo cujos produtos/itens contenham o nome
    /// do item adicional; "em dia" = sem cobrança vencida sinalizada no contrato.
    /// </summary>
    private StatusSuperlogica Interpretar(string json)
    {
        using var doc = JsonDocument.Parse(json);
        var raiz = doc.RootElement;
        // A API costuma devolver { data: [ ... ] } ou um array direto.
        var contratos = raiz.ValueKind == JsonValueKind.Array ? raiz
            : raiz.TryGetProperty("data", out var d) ? d : default;

        if (contratos.ValueKind != JsonValueKind.Array || contratos.GetArrayLength() == 0)
            return new StatusSuperlogica(Encontrado: false, TemItemSigedash: false, EmDia: false);

        var temItem = false;
        var emDia = true;
        foreach (var c in contratos.EnumerateArray())
        {
            // item adicional SigeDash presente em algum produto/item do contrato?
            var textoContrato = c.GetRawText();
            if (textoContrato.Contains(_itemAdicional, StringComparison.OrdinalIgnoreCase))
                temItem = true;

            // inadimplência: sinalizadores comuns (a confirmar os campos reais).
            if (Sinaliza(c, "inadimplente") || Sinaliza(c, "vencid") || Sinaliza(c, "bloqueado"))
                emDia = false;
        }
        return new StatusSuperlogica(Encontrado: true, TemItemSigedash: temItem, EmDia: emDia);
    }

    private static bool Sinaliza(JsonElement el, string chaveParcial)
    {
        foreach (var p in el.EnumerateObject())
            if (p.Name.Contains(chaveParcial, StringComparison.OrdinalIgnoreCase)
                && p.Value.ValueKind == JsonValueKind.String
                && (p.Value.GetString() == "1" || string.Equals(p.Value.GetString(), "true", StringComparison.OrdinalIgnoreCase)))
                return true;
        return false;
    }
}
