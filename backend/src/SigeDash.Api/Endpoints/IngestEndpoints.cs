using System.IO.Compression;
using System.Text;
using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;
using SigeDash.Api.Modelos;

namespace SigeDash.Api.Endpoints;

/// <summary>Recebe os snapshots do agente. Autentica pela chave do cliente (header).</summary>
public static class IngestEndpoints
{
    public static void MapIngest(this IEndpointRouteBuilder app)
    {
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
