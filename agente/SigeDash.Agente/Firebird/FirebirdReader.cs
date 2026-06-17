using System;
using System.Collections.Generic;
using System.Data;
using System.Threading;
using FirebirdSql.Data.FirebirdClient;

namespace SigeDash.Agente.Firebird
{
    /// <summary>
    /// Leitura read-only no Firebird 2.5 com foco em memoria:
    /// - FbDataReader (streaming, linha a linha) — nunca DataSet/DataTable inteiro;
    /// - transacao ReadCommitted/ReadOnly;
    /// - using em conexao, comando e reader (dispose deterministico, ajuda o GC);
    /// - charset ISO8859_1 vem da connection string (banco e Latin1).
    /// </summary>
    public sealed class FirebirdReader
    {
        private readonly string _connectionString;

        public FirebirdReader(string connectionString)
        {
            _connectionString = connectionString;
        }

        /// <summary>
        /// Executa o SQL e devolve as linhas como dicionarios (coluna -> valor).
        /// O callback 'porLinha' permite consumir em streaming sem materializar tudo,
        /// mas aqui devolvemos lista pois os indicadores do dashboard sao pequenos (TOP N).
        /// </summary>
        public List<Dictionary<string, object>> Consultar(
            string sql,
            IReadOnlyDictionary<string, object> parametros,
            CancellationToken ct)
        {
            var linhas = new List<Dictionary<string, object>>();

            using (var conn = new FbConnection(_connectionString))
            {
                conn.Open();
                using (var tx = conn.BeginTransaction(IsolationLevel.ReadCommitted))
                using (var cmd = new FbCommand(sql, conn, tx))
                {
                    cmd.CommandTimeout = 120;
                    if (parametros != null)
                        foreach (var p in parametros)
                            cmd.Parameters.AddWithValue("@" + p.Key, p.Value ?? DBNull.Value);

                    using (var reader = cmd.ExecuteReader())
                    {
                        var nomes = new string[reader.FieldCount];
                        for (var i = 0; i < reader.FieldCount; i++)
                            nomes[i] = reader.GetName(i);

                        while (reader.Read())
                        {
                            ct.ThrowIfCancellationRequested();
                            var linha = new Dictionary<string, object>(reader.FieldCount);
                            for (var i = 0; i < reader.FieldCount; i++)
                            {
                                var valor = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                linha[nomes[i]] = valor;
                            }
                            linhas.Add(linha);
                        }
                    }
                    tx.Commit();
                }
            }
            return linhas;
        }
    }
}
