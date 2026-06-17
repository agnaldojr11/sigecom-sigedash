using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace SigeDash.Agente.Config
{
    /// <summary>Configuracao do agente, carregada de Config/agente.config.json.</summary>
    public sealed class AppConfig
    {
        public string FirebirdConnectionString { get; set; }
        public int CodigoEmpresa { get; set; } = 1;
        public string BackendUrl { get; set; }
        public string ChaveCliente { get; set; }
        public string PastaSql { get; set; } = "Indicadores/sql";
        public List<IndicadorConfig> Indicadores { get; set; } = new List<IndicadorConfig>();

        public static AppConfig Carregar()
        {
            var baseDir = AppDomain.CurrentDomain.BaseDirectory;
            var cfg = LerJson<AppConfig>(Path.Combine(baseDir, "Config", "agente.config.json"));

            // os indicadores (handle, cadencia, tipo, arquivo sql) ficam em arquivo proprio
            var inds = LerJson<List<IndicadorConfig>>(Path.Combine(baseDir, "Indicadores", "indicadores.json"));
            cfg.Indicadores = inds ?? new List<IndicadorConfig>();
            return cfg;
        }

        private static T LerJson<T>(string caminho)
        {
            using (var fs = File.OpenRead(caminho))
                return JsonSerializer.Deserialize<T>(fs, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
        }
    }

    /// <summary>Metadado de um indicador. O SQL vive em arquivo separado (ArquivoSql).</summary>
    public sealed class IndicadorConfig
    {
        public string Handle { get; set; }
        public string Titulo { get; set; }
        public string Tipo { get; set; }            // doughnut | bar | list | info | pie ...
        public int CadenciaMinutos { get; set; } = 10;
        public string ArquivoSql { get; set; }       // ex: vendas/total_vendas_hoje.sql
    }
}
