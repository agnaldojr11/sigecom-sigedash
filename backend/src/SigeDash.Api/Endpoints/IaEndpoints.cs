using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace SigeDash.Api.Endpoints;

public static class IaEndpoints
{
    public static void MapIa(this WebApplication app)
    {
        app.MapPost("/ia/query", QueryIA).RequireAuthorization().RequireRateLimiting("ia");
    }

    private static async Task<IResult> QueryIA(
        IaQueryDto dto,
        IConfiguration config,
        IHttpClientFactory httpFactory,
        CancellationToken ct)
    {
        var contextoTexto = FormatarContexto(dto.Contexto);
        var systemPrompt =
            "Você é um assistente de BI integrado ao SigeDash, sistema de indicadores empresariais. " +
            "Responda em português, de forma direta e objetiva, com base somente nos dados abaixo. " +
            "Use linguagem empresarial simples. Se a informação não estiver disponível, diga claramente.\n\n" +
            "DADOS ATUAIS DO PAINEL:\n" + contextoTexto;

        var http = httpFactory.CreateClient("ia");

        // Provedor OpenAI-compatible (OpenRouter, DeepSeek, Moonshot/Kimi, etc.) — preferido.
        // Basta configurar Ia:ApiKey + Ia:Model (+ Ia:BaseUrl, default OpenRouter).
        var iaKey = config["Ia:ApiKey"];
        if (!string.IsNullOrWhiteSpace(iaKey))
            return await QueryOpenAICompat(http, config, iaKey!, systemPrompt, dto.Pergunta, ct);

        // Fallback legado: Anthropic (Claude) direto.
        var claudeKey = config["Claude:ApiKey"];
        if (!string.IsNullOrWhiteSpace(claudeKey))
            return await QueryAnthropic(http, claudeKey!, systemPrompt, dto.Pergunta, ct);

        return Results.Problem(
            "Assistente IA não configurado. Adicione Ia:ApiKey e Ia:Model em appsettings.",
            statusCode: 503);
    }

    // Padrão de mercado (OpenAI /chat/completions). Compatível com OpenRouter, DeepSeek e Moonshot/Kimi.
    private static async Task<IResult> QueryOpenAICompat(
        HttpClient http, IConfiguration config, string apiKey,
        string systemPrompt, string pergunta, CancellationToken ct)
    {
        var baseUrl = (config["Ia:BaseUrl"] ?? "https://openrouter.ai/api/v1").TrimEnd('/');
        var model   = config["Ia:Model"]   ?? "openrouter/free";

        var payload = new
        {
            model,
            max_tokens = 512,
            messages = new[]
            {
                new { role = "system", content = systemPrompt },
                new { role = "user",   content = pergunta }
            }
        };

        var req = new HttpRequestMessage(HttpMethod.Post, baseUrl + "/chat/completions");
        req.Headers.Add("Authorization", "Bearer " + apiKey);
        // Cabeçalhos recomendados pelo OpenRouter (ignorados pelos demais provedores).
        req.Headers.Add("HTTP-Referer", "https://sigedash.com.br");
        req.Headers.Add("X-Title", "SigeDash");
        req.Content = JsonContent.Create(payload);

        HttpResponseMessage res;
        try { res = await http.SendAsync(req, ct); }
        catch (Exception ex) { return Results.Problem("Erro ao conectar com a API de IA: " + ex.Message, statusCode: 502); }

        if (!res.IsSuccessStatusCode)
        {
            // Extrai a mensagem de erro do provedor (formato OpenAI: { error: { message } }).
            var raw = await res.Content.ReadAsStringAsync(ct);
            var msg = raw;
            try
            {
                var e = JsonSerializer.Deserialize<JsonElement>(raw);
                if (e.TryGetProperty("error", out var er) && er.TryGetProperty("message", out var m))
                    msg = m.GetString() ?? raw;
            }
            catch { /* mantem o corpo cru */ }
            return Results.Problem("IA (" + (int)res.StatusCode + "): " + msg, statusCode: 502);
        }

        var json = await res.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: ct);
        if (!json.TryGetProperty("choices", out var choices) || choices.GetArrayLength() == 0)
            return Results.Problem("IA: o provedor não retornou conteúdo (verifique o modelo em Ia:Model).", statusCode: 502);
        var texto = choices[0].GetProperty("message").GetProperty("content").GetString();
        return Results.Ok(new { resposta = string.IsNullOrWhiteSpace(texto) ? "(sem resposta)" : texto });
    }

    // Fallback: Anthropic Messages API (formato próprio).
    private static async Task<IResult> QueryAnthropic(
        HttpClient http, string apiKey, string systemPrompt, string pergunta, CancellationToken ct)
    {
        var payload = new
        {
            model = "claude-haiku-4-5-20251001",
            max_tokens = 512,
            system = systemPrompt,
            messages = new[] { new { role = "user", content = pergunta } }
        };

        var req = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages");
        req.Headers.Add("x-api-key", apiKey);
        req.Headers.Add("anthropic-version", "2023-06-01");
        req.Content = JsonContent.Create(payload);

        HttpResponseMessage res;
        try { res = await http.SendAsync(req, ct); }
        catch (Exception ex) { return Results.Problem("Erro ao conectar com a API de IA: " + ex.Message, statusCode: 502); }

        if (!res.IsSuccessStatusCode)
        {
            var err = await res.Content.ReadAsStringAsync(ct);
            return Results.Problem("Erro da API de IA (" + (int)res.StatusCode + "): " + err, statusCode: 502);
        }

        var json = await res.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: ct);
        var texto = json.GetProperty("content")[0].GetProperty("text").GetString() ?? "(sem resposta)";
        return Results.Ok(new { resposta = texto });
    }

    private static string FormatarContexto(List<ContextoItemDto>? itens)
    {
        if (itens == null || itens.Count == 0) return "(nenhum dado disponível)";
        var sb = new StringBuilder();
        foreach (var it in itens)
            sb.AppendLine("• " + it.Titulo + ": " + it.Resumo);
        return sb.ToString();
    }
}

public record IaQueryDto(string Pergunta, List<ContextoItemDto>? Contexto);
public record ContextoItemDto(string Titulo, string Resumo);
