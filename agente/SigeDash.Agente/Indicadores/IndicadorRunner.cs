using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using SigeDash.Agente.Config;
using SigeDash.Agente.Firebird;
using SigeDash.Agente.Modelos;

namespace SigeDash.Agente.Indicadores
{
    /// <summary>
    /// Le o arquivo .sql do indicador, injeta parametros (empresa/datas) e executa.
    /// Devolve um Snapshot que ja sabe se serializar para um stream comprimido.
    /// </summary>
    public sealed class IndicadorRunner
    {
        private readonly AppConfig _config;
        private readonly FirebirdReader _fb;
        private readonly string _baseDir;

        public IndicadorRunner(AppConfig config)
        {
            _config = config;
            _fb = new FirebirdReader(config.FirebirdConnectionString);
            _baseDir = AppDomain.CurrentDomain.BaseDirectory;
        }

        public Snapshot Executar(IndicadorConfig ind, CancellationToken ct)
        {
            var caminhoSql = Path.Combine(_baseDir, _config.PastaSql.Replace('/', Path.DirectorySeparatorChar), ind.ArquivoSql.Replace('/', Path.DirectorySeparatorChar));
            var sql = File.ReadAllText(caminhoSql);

            // Datas sao embutidas como literais CAST para evitar bug do FirebirdSql 7.x:
            // AddWithValue mapeia DateTime para TIMESTAMP, mas o provider passa todos os
            // parametros de forma posicional e falha quando um slot espera DATE vs TIMESTAMP.
            // Embute as datas diretamente (valores calculados pelo agente, sem risco de injection).
            var hoje = DateTime.Today;
            var iniSemana = hoje.AddDays(-(int)hoje.DayOfWeek);
            var iniMes   = new DateTime(hoje.Year, hoje.Month, 1);

            sql = SubstDataLiteral(sql, "@INI_HOJE",   hoje);
            sql = SubstDataLiteral(sql, "@FIM_HOJE",   hoje.AddDays(1));
            sql = SubstDataLiteral(sql, "@INI_SEMANA", iniSemana);
            sql = SubstDataLiteral(sql, "@FIM_SEMANA", iniSemana.AddDays(7));
            sql = SubstDataLiteral(sql, "@INI_MES",    iniMes);
            sql = SubstDataLiteral(sql, "@FIM_MES",    iniMes.AddMonths(1));

            // @EMPRESA permanece como parametro ADO.NET normal (inteiro, sem o bug de tipo).
            var parametros = new Dictionary<string, object> { ["EMPRESA"] = _config.CodigoEmpresa };

            var linhas = _fb.Consultar(sql, parametros, ct);
            return new Snapshot(ind.Handle, ind.Tipo, ind.Titulo, linhas);
        }

        private static string SubstDataLiteral(string sql, string token, DateTime data)
        {
            // Substitui @TOKEN por CAST('YYYY-MM-DD' AS DATE) no texto SQL.
            // Usa Regex para case-insensitive no .NET 4.8 (string.Replace(,,StringComparison) so existe no .NET 5+).
            var literal = "CAST('" + data.ToString("yyyy-MM-dd") + "' AS DATE)";
            return System.Text.RegularExpressions.Regex.Replace(
                sql,
                System.Text.RegularExpressions.Regex.Escape(token),
                literal,
                System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        }
    }
}
