using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Modelos;
using SigeDash.Central.Seguranca;

namespace SigeDash.Central.Endpoints;

/// <summary>
/// Aba INSTALAÇÕES — relatórios que os instaladores enviam (sucesso, avisos, falha, bloqueado na
/// pré-verificação). O suporte vê a etapa e o motivo de cada falha sem acessar o servidor do cliente.
/// Tudo requer login no painel.
/// </summary>
public static class InstalacoesEndpoints
{
    public static void MapInstalacoes(this IEndpointRouteBuilder app)
    {
        // Lista resumida (sem log), mais recentes primeiro. ?problemas=true → só falha/bloqueado/avisos.
        app.MapGet("/painel/instalacoes", async (bool? problemas, int? clienteId, CentralDbContext db, CancellationToken ct) =>
        {
            var q = db.RelatoriosInstalacao.AsNoTracking().AsQueryable();
            if (problemas == true) q = q.Where(r => r.Status != "sucesso");
            if (clienteId is not null) q = q.Where(r => r.ClienteId == clienteId);

            var lista = await q
                .OrderByDescending(r => r.RecebidoEm)
                .Take(200)
                .Select(r => new
                {
                    r.Id, r.RecebidoEm, r.ClienteId, r.Tipo, r.Nome, r.Cnpj, r.Versao, r.Maquina,
                    r.Status, r.Etapa, r.Mensagem, r.Bloqueios, r.DuracaoSeg
                })
                .ToListAsync(ct);
            return Results.Ok(lista);
        }).RequireAuthorization();

        // Detalhe completo: pré-verificação + avisos + log mascarado.
        app.MapGet("/painel/instalacoes/{id:long}", async (long id, CentralDbContext db, CancellationToken ct) =>
        {
            var r = await db.RelatoriosInstalacao.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
            return r is null ? Results.NotFound(new { erro = "Relatório não encontrado." }) : Results.Ok(r);
        }).RequireAuthorization();

        // Excluir relatório (ex.: testes) — só admin, auditado.
        app.MapDelete("/painel/instalacoes/{id:long}", async (long id, ClaimsPrincipal user, CentralDbContext db) =>
        {
            var (eu, erro) = await AutorizacaoPainel.ExigeAdminAsync(user, db);
            if (erro is not null) return erro;
            var r = await db.RelatoriosInstalacao.FirstOrDefaultAsync(x => x.Id == id);
            if (r is null) return Results.NotFound();
            db.RelatoriosInstalacao.Remove(r);
            db.LogsAuditoria.Add(new LogAuditoria
            {
                Usuario = eu!.Login, Acao = "relatorio_instalacao_excluido", ClienteId = r.ClienteId,
                Detalhe = $"{r.Nome}: relatório #{r.Id} ({r.Status}, {r.RecebidoEm:yyyy-MM-dd HH:mm}) excluído"
            });
            await db.SaveChangesAsync();
            return Results.NoContent();
        }).RequireAuthorization();
    }
}
