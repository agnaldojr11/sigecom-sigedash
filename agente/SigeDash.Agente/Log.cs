using System;
using System.IO;

namespace SigeDash.Agente
{
    /// <summary>Log minimalista em arquivo (rotacao diaria simples). Sem dependencias externas.</summary>
    internal static class Log
    {
        private static readonly object _lock = new object();
        private static string Arquivo =>
            Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "logs", "agente-" + DateTime.Today.ToString("yyyyMMdd") + ".log");

        public static void Info(string msg) => Escrever("INFO", msg);
        public static void Erro(string msg) => Escrever("ERRO", msg);

        private static void Escrever(string nivel, string msg)
        {
            try
            {
                var dir = Path.GetDirectoryName(Arquivo);
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                lock (_lock)
                    File.AppendAllText(Arquivo, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}  {nivel}  {msg}{Environment.NewLine}");
            }
            catch { /* log nunca derruba o servico */ }
        }
    }
}
