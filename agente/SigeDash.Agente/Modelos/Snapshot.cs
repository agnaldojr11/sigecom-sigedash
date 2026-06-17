using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text.Json;

namespace SigeDash.Agente.Modelos
{
    /// <summary>
    /// Resultado de um indicador pronto para envio. Implementa IDisposable porque
    /// expoe um stream comprimido (gzip) que e descartado apos o POST.
    /// A serializacao usa Utf8JsonWriter direto no GZipStream — nao monta string JSON
    /// inteira em memoria (importante quando ha varias lojas/indicadores).
    /// </summary>
    public sealed class Snapshot : IDisposable
    {
        public string Handle { get; }
        public string Tipo { get; }
        public string Titulo { get; }
        public DateTime GeradoEm { get; }
        private readonly List<Dictionary<string, object>> _linhas;
        private MemoryStream _buffer;

        public Snapshot(string handle, string tipo, string titulo, List<Dictionary<string, object>> linhas)
        {
            Handle = handle;
            Tipo = tipo;
            Titulo = titulo;
            GeradoEm = DateTime.UtcNow;
            _linhas = linhas;
        }

        /// <summary>Stream gzip do JSON, pronto para o corpo do POST. Reposiciona no inicio.</summary>
        public Stream AbrirConteudoGzip()
        {
            if (_buffer == null)
            {
                _buffer = new MemoryStream();
                using (var gz = new GZipStream(_buffer, CompressionLevel.Optimal, leaveOpen: true))
                using (var w = new Utf8JsonWriter(gz))
                {
                    w.WriteStartObject();
                    w.WriteString("handle", Handle);
                    w.WriteString("tipo", Tipo);
                    w.WriteString("titulo", Titulo);
                    w.WriteString("geradoEm", GeradoEm.ToString("o"));
                    w.WritePropertyName("dados");
                    w.WriteStartArray();
                    foreach (var linha in _linhas)
                    {
                        w.WriteStartObject();
                        foreach (var kv in linha)
                            EscreverValor(w, kv.Key, kv.Value);
                        w.WriteEndObject();
                    }
                    w.WriteEndArray();
                    w.WriteEndObject();
                }
            }
            _buffer.Position = 0;
            return _buffer;
        }

        private static void EscreverValor(Utf8JsonWriter w, string nome, object valor)
        {
            switch (valor)
            {
                case null: w.WriteNull(nome); break;
                case string s: w.WriteString(nome, s); break;
                case bool b: w.WriteBoolean(nome, b); break;
                case DateTime dt: w.WriteString(nome, dt.ToString("o")); break;
                case decimal dec: w.WriteNumber(nome, dec); break;
                case double d: w.WriteNumber(nome, d); break;
                case float f: w.WriteNumber(nome, f); break;
                case short sh: w.WriteNumber(nome, sh); break;
                case int i: w.WriteNumber(nome, i); break;
                case long l: w.WriteNumber(nome, l); break;
                default: w.WriteString(nome, Convert.ToString(valor, System.Globalization.CultureInfo.InvariantCulture)); break;
            }
        }

        public void Dispose()
        {
            _buffer?.Dispose();
            _buffer = null;
        }
    }
}
