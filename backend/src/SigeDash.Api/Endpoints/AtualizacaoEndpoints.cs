using System.Diagnostics;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;

namespace SigeDash.Api.Endpoints;

/// <summary>
/// Atualizacao in-app (somente ADMIN). O PWA consulta o status (versao instalada x ultima release)
/// e, quando ha versao nova, o admin dispara a instalacao com um clique. A aplicacao roda via
/// Task Scheduler (tarefa SYSTEM registrada no install), independente do processo do backend —
/// assim o backend consegue ser sobrescrito/reiniciado durante a atualizacao.
/// </summary>
public static class AtualizacaoEndpoints
{
    // Cache da consulta ao GitHub (evita bater na API a cada request / limite de taxa).
    private static string? _cacheVersao;
    private static DateTime _cacheEm = DateTime.MinValue;
    private static readonly TimeSpan CacheTtl = TimeSpan.FromMinutes(30);

    public static void MapAtualizacao(this IEndpointRouteBuilder app, IConfiguration config)
    {
        var repo     = config["Update:Repo"]     ?? "agnaldojr11/sigecom-sigedash";
        var taskName = config["Update:TaskName"] ?? "SigeDash-Aplicar";

        // Status: versao instalada, ultima disponivel e se ha atualizacao.
        app.MapGet("/admin/atualizacao/status", async (
            ClaimsPrincipal user, AppDbContext db, IHttpClientFactory httpFactory, CancellationToken ct) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();

            var atual      = VersaoInstalada();
            var disponivel = await UltimaVersaoAsync(httpFactory, repo, ct);

            bool temUpdate = false;
            if (disponivel is not null
                && Version.TryParse(atual, out var va)
                && Version.TryParse(disponivel, out var vd))
                temUpdate = vd > va;

            return Results.Ok(new
            {
                versaoAtual           = atual,
                versaoDisponivel      = disponivel,
                atualizacaoDisponivel = temUpdate
            });
        }).RequireAuthorization();

        // Aplica: dispara a tarefa agendada (SYSTEM) que baixa e instala. Retorna 202 (assincrono).
        app.MapPost("/admin/atualizacao/aplicar", async (
            ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();

            try
            {
                // Nome da tarefa vem da config (fixo, sem entrada do usuario) — sem superficie de injecao.
                var psi = new ProcessStartInfo("schtasks.exe", $"/Run /TN \"{taskName}\"")
                {
                    UseShellExecute        = false,
                    CreateNoWindow         = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError  = true
                };
                using var proc = Process.Start(psi);
                if (proc is null)
                    return Results.Problem("Nao foi possivel iniciar o atualizador.", statusCode: 500);

                await proc.WaitForExitAsync();
                if (proc.ExitCode != 0)
                {
                    var err = await proc.StandardError.ReadToEndAsync();
                    return Results.Problem(
                        "Falha ao disparar a atualizacao (schtasks " + proc.ExitCode + "): " + err,
                        statusCode: 500);
                }
            }
            catch (Exception ex)
            {
                return Results.Problem("Erro ao iniciar a atualizacao: " + ex.Message, statusCode: 500);
            }

            // 202: a instalacao segue em background; o backend sera parado/reiniciado pela tarefa.
            return Results.Accepted(value: new { iniciado = true });
        }).RequireAuthorization();
    }

    private static string VersaoInstalada()
    {
        try
        {
            var caminho = Path.Combine(AppContext.BaseDirectory, "version.txt");
            if (File.Exists(caminho))
            {
                var v = File.ReadAllText(caminho).Trim();
                if (!string.IsNullOrWhiteSpace(v)) return v;
            }
        }
        catch { /* ignora */ }
        return "0.0.0";
    }

    private static async Task<string?> UltimaVersaoAsync(IHttpClientFactory httpFactory, string repo, CancellationToken ct)
    {
        if (_cacheVersao is not null && DateTime.UtcNow - _cacheEm < CacheTtl)
            return _cacheVersao;

        try
        {
            var http = httpFactory.CreateClient("ia");
            var req  = new HttpRequestMessage(HttpMethod.Get,
                $"https://api.github.com/repos/{repo}/releases/latest");
            req.Headers.Add("User-Agent", "SigeDash-Updater/1.0");
            req.Headers.Add("Accept", "application/vnd.github+json");

            using var res = await http.SendAsync(req, ct);
            if (!res.IsSuccessStatusCode) return _cacheVersao; // mantem cache anterior (offline-tolerante)

            var json = await res.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: ct);
            var tag  = json.TryGetProperty("tag_name", out var t) ? t.GetString() : null;
            if (string.IsNullOrWhiteSpace(tag)) return _cacheVersao;

            _cacheVersao = tag!.TrimStart('v', 'V');
            _cacheEm     = DateTime.UtcNow;
            return _cacheVersao;
        }
        catch
        {
            return _cacheVersao; // rede indisponivel: usa o ultimo conhecido (ou null)
        }
    }

    // Rele o tipo do usuario no banco (nao confia so no claim, que pode estar obsoleto).
    private static async Task<bool> EhAdminAtual(ClaimsPrincipal user, AppDbContext db)
    {
        if (!int.TryParse(user.FindFirstValue("usuario_id"), out var uid)) return false;
        var u = await db.UsuariosApp.Where(x => x.Id == uid)
            .Select(x => new { x.EhAdmin, x.Ativo }).FirstOrDefaultAsync();
        return u is not null && u.Ativo && u.EhAdmin;
    }
}
