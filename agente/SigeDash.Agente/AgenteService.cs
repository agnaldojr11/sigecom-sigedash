using System;
using System.Collections.Generic;
using System.ServiceProcess;
using System.Threading;
using System.Threading.Tasks;
using SigeDash.Agente.Config;
using SigeDash.Agente.Envio;
using SigeDash.Agente.Firebird;
using SigeDash.Agente.Indicadores;

namespace SigeDash.Agente
{
    /// <summary>
    /// Servico que orquestra a execucao dos indicadores conforme a cadencia de cada um
    /// e envia os snapshots ao backend. Um unico timer leve; nada fica residente em memoria
    /// alem do necessario (resultados sao serializados direto para stream).
    /// </summary>
    public sealed class AgenteService : ServiceBase
    {
        private readonly AppConfig _config;
        private readonly IndicadorRunner _runner;
        private readonly BackendClient _backend;
        private Timer _timer;
        private CancellationTokenSource _cts;
        private readonly Dictionary<string, DateTime> _proximaExecucao = new Dictionary<string, DateTime>();
        private int _emExecucao; // guarda contra reentrancia do timer

        public AgenteService()
        {
            ServiceName = "SigeDashAgente";
            _config = AppConfig.Carregar();
            _backend = new BackendClient(_config);
            _runner = new IndicadorRunner(_config);
        }

        protected override void OnStart(string[] args) => Iniciar();
        protected override void OnStop() => Parar();

        public void IniciarManual() => Iniciar();
        public void PararManual() => Parar();

        private void Iniciar()
        {
            Log.Info("Agente iniciando. Cliente=" + _config.ChaveCliente + " Empresa=" + _config.CodigoEmpresa);
            _cts = new CancellationTokenSource();
            var agora = DateTime.Now;
            foreach (var ind in _config.Indicadores)
                _proximaExecucao[ind.Handle] = agora; // roda todos na primeira passada
            // tick a cada 30s; cada indicador decide se ja "venceu" sua cadencia
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
            if (Interlocked.Exchange(ref _emExecucao, 1) == 1) return; // ja rodando
            try
            {
                var agora = DateTime.Now;
                foreach (var ind in _config.Indicadores)
                {
                    if (_cts.IsCancellationRequested) break;
                    if (_proximaExecucao[ind.Handle] > agora) continue;

                    try
                    {
                        // executa e ja serializa o snapshot para um stream comprimido
                        using (var snapshot = _runner.Executar(ind, _cts.Token))
                        {
                            await _backend.EnviarAsync(ind.Handle, snapshot, _cts.Token).ConfigureAwait(false);
                        }
                        Log.Info("Indicador OK: " + ind.Handle);
                    }
                    catch (Exception ex)
                    {
                        Log.Erro("Falha no indicador " + ind.Handle + ": " + ex.Message);
                    }
                    finally
                    {
                        _proximaExecucao[ind.Handle] = agora.AddMinutes(ind.CadenciaMinutos);
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
