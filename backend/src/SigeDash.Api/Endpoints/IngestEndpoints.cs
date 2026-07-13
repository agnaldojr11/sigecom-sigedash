using System.IO.Compression;
using System.Text;
using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;
using SigeDash.Api.Modelos;

namespace SigeDash.Api.Endpoints;

public record UsuarioSyncDto(string Login, string SenhaApp, int CodigoTipo = 0);

/// <summary>Recebe os snapshots e usuarios sincronizados do agente. Autentica pela chave do cliente (header).</summary>
public static class IngestEndpoints
{
    public static void MapIngest(this IEndpointRouteBuilder app)
    {
        // Sincroniza a lista de usuarios do Firebird (USUARIO.SENHA_APP) para o backend
        app.MapPost("/ingest/usuarios", async (
            List<UsuarioSyncDto> usuarios, HttpRequest req, AppDbContext db) =>
        {
            var chave = req.Headers["X-SigeDash-Key"].ToString();
            var cliente = await db.Clientes.FirstOrDefaultAsync(c => c.ChaveApi == chave && c.Ativo);
            if (cliente is null) return Results.Unauthorized();

            foreach (var u in usuarios)
            {
                var existing = await db.UsuariosApp
                    .FirstOrDefaultAsync(x => x.ClienteId == cliente.Id && x.Login == u.Login);
                if (existing is null)
                    // Novo usuario: SecoesPermitidas fica null (nada liberado ate o admin configurar).
                    db.UsuariosApp.Add(new UsuarioApp
                    {
                        ClienteId = cliente.Id, Login = u.Login,
                        SenhaApp = u.SenhaApp, CodigoTipo = u.CodigoTipo
                    });
                else
                {
                    // Atualiza senha e tipo; NUNCA sobrescreve as permissoes ja configuradas pelo admin.
                    existing.SenhaApp   = u.SenhaApp;
                    existing.CodigoTipo = u.CodigoTipo;
                }
            }
            await db.SaveChangesAsync();
            return Results.Ok(new { sincronizados = usuarios.Count });
        });

        app.MapPost("/ingest/{codigoEmpresa:int}/{handle}", async (
            int codigoEmpresa, string handle, HttpRequest req, AppDbContext db) =>
        {
            // 1) autentica o agente pela chave do cliente
            var chave = req.Headers["X-SigeDash-Key"].ToString();
            var cliente = await db.Clientes.FirstOrDefaultAsync(c => c.ChaveApi == chave && c.Ativo);
            if (cliente is null) return Results.Unauthorized();

            // 2) le o corpo (pode vir gzip do agente) sem materializar varias copias
            string json;
            Stream body = req.Body;
            if (req.Headers.ContentEncoding.ToString().Contains("gzip"))
                body = new GZipStream(body, CompressionMode.Decompress);
            using (var sr = new StreamReader(body, Encoding.UTF8))
                json = await sr.ReadToEndAsync();

            // 3) grava o snapshot (append; o PWA le sempre o mais recente)
            db.Snapshots.Add(new Snapshot
            {
                ClienteId = cliente.Id,
                CodigoEmpresa = codigoEmpresa,
                IndicadorHandle = handle,
                PayloadJson = json,
                GeradoEm = DateTime.UtcNow,   // TODO: extrair "geradoEm" do payload
                RecebidoEm = DateTime.UtcNow
            });
            await db.SaveChangesAsync();
            return Results.Ok(new { ok = true });
        });
    }
}
