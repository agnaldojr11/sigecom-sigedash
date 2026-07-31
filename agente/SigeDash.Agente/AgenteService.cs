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

                // OBS.: a sincronizacao de USUARIOS do SIGECOM foi removida — os usuarios do SigeDash
                // sao nativos (criados pelo ADM da empresa, senha BCrypt). O agente so envia indicadores.

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

    }
}
