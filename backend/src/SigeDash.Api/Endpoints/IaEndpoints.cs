using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace SigeDash.Api.Endpoints;

public static class IaEndpoints
{
    public static void MapIa(this WebApplication app)
    {
        app.MapPost("/ia/query", QueryIA).RequireAuthorization();
    }

    private static async Task<IResult> QueryIA(
        IaQueryDto dto,
        IConfiguration config,
        IHttpClientFactory httpFactory,
        CancellationToken ct)
    {
        var apiKey = config["Claude:ApiKey"];
        if (string.IsNullOrWhiteSpace(apiKey))
            return Results.Problem(
                "Assistente IA não configurado. Adicione Claude:ApiKey em appsettings.json.",
                statusCode: 503);

        var contextoTexto = FormatarContexto(dto.Contexto);
        var systemPrompt =
            "Você é um assistente de BI integrado ao SigeDash, sistema de indicadores empresariais. " +
            "Responda em português, de forma direta e objetiva, com base somente nos dados abaixo. " +
            "Use linguagem empresarial simples. Se a informação não estiver disponível, diga claramente.\n\n" +
            "DADOS ATUAIS DO PAINEL:\n" + contextoTexto;

        var payload = new
        {
            model = "claude-haiku-4-5-20251001",
            max_tokens = 512,
            system = systemPrompt,
            messages = new[] { new { role = "user", content = dto.Pergunta } }
        };

        var http = httpFactory.CreateClient("claude");
        var req = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages");
        req.Headers.Add("x-api-key", apiKey);
        req.Headers.Add("anthropic-version", "2023-06-01");
        req.Content = JsonContent.Create(payload);

        HttpResponseMessage res;
        try
        {
            res = await http.SendAsync(req, ct);
        }
        catch (Exception ex)
        {
            return Results.Problem("Erro ao conectar com a API de IA: " + ex.Message, statusCode: 502);
        }

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
