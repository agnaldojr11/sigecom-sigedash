using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.ServiceProcess;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using SigeDash.Agente.Config;
using SigeDash.Agente.Envio;
using SigeDash.Agente.Firebird;
using SigeDash.Agente.Indicadores;

namespace SigeDash.Agente
{
    public sealed class AgenteService : ServiceBase
    {
        private readonly AppConfig _config;
        private readonly IndicadorRunner _runner;
        private readonly BackendClient _backend;
        private readonly FirebirdReader _reader;
        private Timer _timer;
        private CancellationTokenSource _cts;
        private readonly Dictionary<string, DateTime> _proximaExecucao = new Dictionary<string, DateTime>();
        private DateTime _proximaSincUsers = DateTime.MinValue; // executa imediatamente no primeiro tick
        private int _emExecucao;

        public AgenteService()
        {
            ServiceName = "SigeDashAgente";
            _config  = AppConfig.Carregar();
            _backend = new BackendClient(_config);
            _runner  = new IndicadorRunner(_config);
            _reader  = new FirebirdReader(_config.FirebirdConnectionString);
        }

        protected override void OnStart(string[] args) => Iniciar();
        protected override void OnStop() => Parar();

        public void IniciarManual() => Iniciar();
        public void PararManual()   => Parar();

        private void Iniciar()
        {
            Log.Info("Agente iniciando. Cliente=" + _config.ChaveCliente + " Empresa=" + _config.CodigoEmpresa);
            _cts = new CancellationTokenSource();
            var agora = DateTime.Now;
            foreach (var ind in _config.Indicadores)
                _proximaExecucao[ind.Handle] = agora;
            _timer = new Timer(_ => Tick(), null, TimeSpan.Zero, TimeSpan.FromSeconds(30));
        }

        private void Parar()
        {
            Log.Info("Agente parando.");
            _cts?.Cancel();
            _timer?.Dispose();
            _backend?.Dispose();
        }

        private async void Tick()
        {
            if (Interlocked.Exchange(ref _emExecucao, 1) == 1) return;
            try
            {
                var agora = DateTime.Now;

                // Sincroniza usuarios do Firebird a cada 1 hora (e imediatamente no startup)
                if (_proximaSincUsers <= agora)
                {
                    try
                    {
                        await SincronizarUsuarios().ConfigureAwait(false);
                        _proximaSincUsers = agora.AddHours(1);
                    }
                    catch (Exception ex)
                    {
                        Log.Erro("Falha na sincronizacao de usuarios: " + ex.Message);
                        _proximaSincUsers = agora.AddMinutes(5); // retry em 5 min se falhar
                    }
                }

                foreach (var ind in _config.Indicadores)
                {
                    if (_cts.IsCancellationRequested) break;
                    if (_proximaExecucao[ind.Handle] > agora) continue;

                    try
                    {
                        using (var snapshot = _runner.Executar(ind, _cts.Token))
                        {
                            await _backend.EnviarAsync(ind.Handle, snapshot, _cts.Token).ConfigureAwait(false);
                        }
                        Log.Info("Indicador OK: " + ind.Handle);
                        _proximaExecucao[ind.Handle] = agora.AddMinutes(ind.CadenciaMinutos);
                    }
                    catch (Exception ex)
                    {
                        Log.Erro("Falha no indicador " + ind.Handle + ": " + ex.Message);
                        _proximaExecucao[ind.Handle] = agora.AddMinutes(1); // retry rapido apos falha
                    }
                }
            }
            finally
            {
                Interlocked.Exchange(ref _emExecucao, 0);
            }
        }

        private async Task SincronizarUsuarios()
        {
            // USUARIO.SENHA_APP ja e o SHA1 (hex) da senha do app, definido no SIGECOM.
            // Lemos ele DIRETO (sem decodificar/re-hashear a coluna SENHA): o backend compara
            // com Sha1Hex(senha digitada). Usuarios sem SENHA_APP nao sao sincronizados
            // (precisam ter a senha do app definida no SIGECOM para acessar).
            var linhas = _reader.Consultar(
                "SELECT DISTINCT LOGIN, SENHA_APP, CODIGOTIPO FROM USUARIO WHERE DESATIVADO = 'N'",
                null, CancellationToken.None);

            var usuarios = linhas
                .Select(r =>
                {
                    var login = r.ContainsKey("LOGIN") ? (r["LOGIN"]?.ToString()?.Trim() ?? "") : "";
                    // SHA1 em hex; normaliza para minusculo (o backend compara em minusculo).
                    var senhaApp = r.ContainsKey("SENHA_APP") ? (r["SENHA_APP"]?.ToString()?.Trim()?.ToLowerInvariant() ?? "") : "";
                    int tipo = 0;
                    if (r.ContainsKey("CODIGOTIPO"))
                        int.TryParse(r["CODIGOTIPO"]?.ToString(), out tipo);
                    return new UsuarioSync { Login = login, SenhaApp = senhaApp, CodigoTipo = tipo };
                })
                .Where(u => !string.IsNullOrEmpty(u.Login) && !string.IsNullOrEmpty(u.SenhaApp))
                .GroupBy(u => u.Login).Select(g => g.First())
                .ToList();

            await _backend.SincronizarUsuariosAsync(usuarios, _cts.Token).ConfigureAwait(false);
            Log.Info("Usuarios sincronizados: " + usuarios.Count);
        }
    }
}
