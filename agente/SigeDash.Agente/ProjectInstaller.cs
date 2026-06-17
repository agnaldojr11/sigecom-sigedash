using System.ComponentModel;
using System.Configuration.Install;
using System.ServiceProcess;

namespace SigeDash.Agente
{
    /// <summary>
    /// Permite instalar o servico com: installutil SigeDash.Agente.exe
    /// Roda como LocalSystem; arranca automatico no boot.
    /// </summary>
    [RunInstaller(true)]
    public sealed class ProjectInstaller : Installer
    {
        public ProjectInstaller()
        {
            var processo = new ServiceProcessInstaller { Account = ServiceAccount.LocalSystem };
            var servico = new ServiceInstaller
            {
                ServiceName = "SigeDashAgente",
                DisplayName = "SigeDash Agente",
                Description = "Coleta indicadores do SIGECOM (Firebird, somente leitura) e envia ao backend SigeDash.",
                StartType = ServiceStartMode.Automatic
            };
            Installers.Add(processo);
            Installers.Add(servico);
        }
    }
}
