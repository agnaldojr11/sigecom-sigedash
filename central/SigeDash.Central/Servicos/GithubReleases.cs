using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Caching.Memory;

namespace SigeDash.Central.Servicos;

/// <summary>
/// Cataloga o GitHub Releases do repo de releases (agnaldojr11/sigecom-sigedash) — a Central NÃO
/// hospeda binários. Lista as releases (cacheadas) e resolve o link temporário assinado de cada
/// asset, para o suporte baixar direto do GitHub (sem consumir banda/armazenamento da Railway).
///
/// Requer um token do GitHub (PAT read-only no repo privado) na variável de ambiente do Railway:
/// Github__Token  (ou GITHUB_TOKEN). Sem token, os endpoints de versões respondem 503 amigável.
/// </summary>
public sealed class GithubReleases
{
    private readonly IHttpClientFactory _http;
    private readonly IMemoryCache _cache;
    private readonly string _repo;
    private readonly string? _token;

    private const string CacheKey = "gh-releases";

    public GithubReleases(IHttpClientFactory http, IMemoryCache cache, IConfiguration cfg)
    {
        _http  = http;
        _cache = cache;
        _repo  = cfg["Github:Repo"] ?? "agnaldojr11/sigecom-sigedash";
        _token = cfg["Github:Token"] ?? Environment.GetEnvironmentVariable("GITHUB_TOKEN");
    }

    public bool Configurado => !string.IsNullOrWhiteSpace(_token);

    /// <summary>Lista as releases (cache de 5 min para não bater no rate limit do GitHub).</summary>
    public async Task<IReadOnlyList<Release>> ListarAsync(CancellationToken ct)
    {
        if (_cache.TryGetValue(CacheKey, out IReadOnlyList<Release>? cached) && cached is not null)
            return cached;

        var req = new HttpRequestMessage(HttpMethod.Get,
            $"https://api.github.com/repos/{_repo}/releases?per_page=30");
        Assinar(req);

        using var cli = _http.CreateClient("github");
        using var res = await cli.SendAsync(req, ct);
        res.EnsureSuccessStatusCode();

        var stream = await res.Content.ReadAsStreamAsync(ct);
        var lista = await JsonSerializer.DeserializeAsync<List<Release>>(stream, cancellationToken: ct)
                    ?? new List<Release>();

        _cache.Set(CacheKey, (IReadOnlyList<Release>)lista, TimeSpan.FromMinutes(5));
        return lista;
    }

    /// <summary>
    /// Resolve a URL temporária assinada (S3) de um asset de repo privado. O GitHub responde 302
    /// com Location quando pedimos o asset com Accept: application/octet-stream. Devolvemos essa URL
    /// ao navegador (que baixa direto do GitHub). Retorna null se o asset não existir/for negado.
    /// </summary>
    public async Task<string?> ResolverDownloadAsync(long assetId, CancellationToken ct)
    {
        var req = new HttpRequestMessage(HttpMethod.Get,
            $"https://api.github.com/repos/{_repo}/releases/assets/{assetId}");
        Assinar(req);
        req.Headers.Accept.Clear();
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/octet-stream"));

        // Handler sem auto-redirect: queremos o Location, não o corpo do S3.
        using var handler = new HttpClientHandler { AllowAutoRedirect = false };
        using var cli = new HttpClient(handler);
        using var res = await cli.SendAsync(req, ct);

        if (res.StatusCode is HttpStatusCode.Redirect or HttpStatusCode.Found
            or HttpStatusCode.TemporaryRedirect or HttpStatusCode.MovedPermanently)
            return res.Headers.Location?.ToString();

        return null;
    }

    private void Assinar(HttpRequestMessage req)
    {
        req.Headers.UserAgent.ParseAdd("SigeDash-Central");
        req.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        req.Headers.Add("X-GitHub-Api-Version", "2022-11-28");
        if (!string.IsNullOrWhiteSpace(_token))
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
    }

    // ── Modelo da resposta do GitHub (só os campos usados) ──────────────────────
    public sealed class Release
    {
        [JsonPropertyName("tag_name")]     public string TagName { get; set; } = "";
        [JsonPropertyName("name")]         public string? Name { get; set; }
        [JsonPropertyName("body")]         public string? Body { get; set; }
        [JsonPropertyName("draft")]        public bool Draft { get; set; }
        [JsonPropertyName("prerelease")]   public bool Prerelease { get; set; }
        [JsonPropertyName("published_at")] public DateTime? PublishedAt { get; set; }
        [JsonPropertyName("assets")]       public List<Asset> Assets { get; set; } = new();
    }

    public sealed class Asset
    {
        [JsonPropertyName("id")]           public long Id { get; set; }
        [JsonPropertyName("name")]         public string Name { get; set; } = "";
        [JsonPropertyName("size")]         public long Size { get; set; }
        [JsonPropertyName("content_type")] public string? ContentType { get; set; }
    }
}
