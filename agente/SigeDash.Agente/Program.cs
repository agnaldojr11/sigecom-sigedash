using System;
using System.ServiceProcess;

namespace SigeDash.Agente
{
    internal static class Program
    {
        /// <summary>
        /// Ponto de entrada. Roda como Windows Service por padrao.
        /// Para depurar no Visual Studio, rode com o argumento --console.
        /// </summary>
        private static void Main(string[] args)
        {
            if (Environment.UserInteractive || ArgsContem(args, "--console"))
            {
                Console.WriteLine("SigeDash Agente — modo console (Ctrl+C para sair).");
                using (var svc = new AgenteService())
                {
                    svc.IniciarManual();
                    Console.WriteLine("Rodando. Pressione ENTER para parar.");
                    Console.ReadLine();
                    svc.PararManual();
                }
                return;
            }

            ServiceBase.Run(new AgenteService());
        }

        private static bool ArgsContem(string[] args, string flag)
        {
            return args != null && Array.Exists(args, a => string.Equals(a, flag, StringComparison.OrdinalIgnoreCase));
        }
    }
}
