using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using SigeDash.Agente.Config;
using SigeDash.Agente.Modelos;

namespace SigeDash.Agente.Envio
{
    public sealed class UsuarioSync
    {
        public string Login      { get; set; }
        public string SenhaApp   { get; set; }
        public int    CodigoTipo { get; set; }   // USUARIO.CODIGOTIPO (1 = Administrador)
    }

    /// <summary>
    /// Envia snapshots e sincroniza usuarios ao backend.
    /// Um HttpClient reutilizado para toda a vida do servico.
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
            var conteudo = new StreamContent(snapshot.AbrirConteudoGzip());
            conteudo.Headers.ContentType = new MediaTypeHeaderValue("application/json");
            conteudo.Headers.ContentEncoding.Add("gzip");

            var url = $"/ingest/{_config.CodigoEmpresa}/{handle}";
            using (var resp = await _http.PostAsync(url, conteudo, ct).ConfigureAwait(false))
            {
                resp.EnsureSuccessStatusCode();
            }
        }

        public async Task SincronizarUsuariosAsync(List<UsuarioSync> usuarios, CancellationToken ct)
        {
            var json = JsonSerializer.Serialize(usuarios, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase
            });
            var conteudo = new StringContent(json, Encoding.UTF8, "application/json");
            using (var resp = await _http.PostAsync("/ingest/usuarios", conteudo, ct).ConfigureAwait(false))
            {
                resp.EnsureSuccessStatusCode();
            }
        }

        public void Dispose() => _http?.Dispose();
    }
}
