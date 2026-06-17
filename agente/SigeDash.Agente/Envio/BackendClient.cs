using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Threading;
using System.Threading.Tasks;
using SigeDash.Agente.Config;
using SigeDash.Agente.Modelos;

namespace SigeDash.Agente.Envio
{
    /// <summary>
    /// Envia snapshots ao backend. UM HttpClient reutilizado para toda a vida do servico
    /// (criar HttpClient por requisicao causa esgotamento de sockets).
    /// </summary>
    public sealed class BackendClient : IDisposable
    {
        private readonly HttpClient _http;
        private readonly AppConfig _config;

        public BackendClient(AppConfig config)
        {
            _config = config;
            _http = new HttpClient { BaseAddress = new Uri(config.BackendUrl), Timeout = TimeSpan.FromSeconds(60) };
            _http.DefaultRequestHeaders.Add("X-SigeDash-Key", config.ChaveCliente);
        }

        public async Task EnviarAsync(string handle, Snapshot snapshot, CancellationToken ct)
        {
            // o stream gzip e do snapshot; StreamContent nao copia para memoria de novo
            var conteudo = new StreamContent(snapshot.AbrirConteudoGzip());
            conteudo.Headers.ContentType = new MediaTypeHeaderValue("application/json");
            conteudo.Headers.ContentEncoding.Add("gzip");

            var url = $"/ingest/{_config.CodigoEmpresa}/{handle}";
            using (var resp = await _http.PostAsync(url, conteudo, ct).ConfigureAwait(false))
            {
                resp.EnsureSuccessStatusCode();
            }
        }

        public void Dispose() => _http?.Dispose();
    }
}
