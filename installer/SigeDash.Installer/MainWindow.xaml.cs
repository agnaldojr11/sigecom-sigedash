using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace SigeDash.Installer;

public partial class MainWindow : Window
{
    private int _step = 1;
    private bool _instalando;
    private Process? _proc;
    private readonly StringBuilder _saida = new();

    private static readonly Brush AccentBrush = new SolidColorBrush(Color.FromRgb(0x3B, 0x82, 0xF6));
    private static readonly Brush FaintBrush  = new SolidColorBrush(Color.FromArgb(0x22, 0xFF, 0xFF, 0xFF));
    private static readonly Brush WhiteBrush  = Brushes.White;
    private static readonly Brush MutedBrush  = new SolidColorBrush(Color.FromRgb(0x9F, 0xB4, 0xE0));

    public MainWindow()
    {
        InitializeComponent();

        TopBar.MouseLeftButtonDown += (_, e) => { if (e.ButtonState == MouseButtonState.Pressed) DragMove(); };
        btnMin.Click    += (_, __) => WindowState = WindowState.Minimized;
        btnClose.Click  += (_, __) => TentarFechar();
        btnCancelar.Click += (_, __) => TentarFechar();
        btnAvancar.Click  += (_, __) => IrPara(2);
        btnVoltar.Click   += (_, __) => IrPara(1);
        btnInstalar.Click += async (_, __) => await InstalarAsync();
        btnConcluir.Click += (_, __) => Close();
        btnProcurar.Click += (_, __) => Procurar();

        IrPara(1);
    }

    // ── Navegação ────────────────────────────────────────────────────────────
    private void IrPara(int step)
    {
        _step = step;
        panelWelcome.Visibility  = step == 1 ? Visibility.Visible : Visibility.Collapsed;
        panelConfig.Visibility   = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        panelProgress.Visibility = step == 3 ? Visibility.Visible : Visibility.Collapsed;
        panelFinish.Visibility   = step == 4 ? Visibility.Visible : Visibility.Collapsed;

        btnVoltar.Visibility   = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        btnCancelar.Visibility = step <= 3 ? Visibility.Visible : Visibility.Collapsed;
        btnAvancar.Visibility  = step == 1 ? Visibility.Visible : Visibility.Collapsed;
        btnInstalar.Visibility = step == 2 ? Visibility.Visible : Visibility.Collapsed;
        btnConcluir.Visibility = step == 4 ? Visibility.Visible : Visibility.Collapsed;

        Realcar(step);
    }

    private void Realcar(int step)
    {
        var nums = new[] { stepNum1, stepNum2, stepNum3, stepNum4 };
        var txts = new[] { stepTxt1, stepTxt2, stepTxt3, stepTxt4 };
        for (int i = 0; i < 4; i++)
        {
            var ativo = (i + 1) == step;
            nums[i].Background = ativo ? AccentBrush : FaintBrush;
            txts[i].Foreground = ativo ? WhiteBrush : MutedBrush;
            txts[i].FontWeight = ativo ? FontWeights.SemiBold : FontWeights.Normal;
        }
    }

    private void Procurar()
    {
        var dlg = new Microsoft.Win32.OpenFileDialog
        {
            Title = "Selecione o banco do SIGECOM",
            Filter = "Banco Firebird (*.FDB)|*.FDB;*.fdb|Todos os arquivos (*.*)|*.*"
        };
        if (dlg.ShowDialog() == true) txtFdb.Text = dlg.FileName;
    }

    private void TentarFechar()
    {
        if (_instalando)
        {
            var r = MessageBox.Show("A instalação está em andamento. Deseja cancelar e sair?",
                "SigeDash", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (r != MessageBoxResult.Yes) return;
            try { _proc?.Kill(true); } catch { }
        }
        Close();
    }

    // ── Instalação ───────────────────────────────────────────────────────────
    private async Task InstalarAsync()
    {
        if (!int.TryParse((txtLimite.Text ?? "").Trim(), out var limite) || limite < 0)
        {
            MessageBox.Show("Informe um número de dispositivos válido (0 = ilimitado).", "SigeDash",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var dir = Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;
        var script = Path.Combine(dir, "instalar-tudo.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show($"instalar-tudo.ps1 não encontrado em:\n{dir}", "SigeDash",
                MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        _instalando = true;
        IrPara(3);
        barProg.IsIndeterminate = true;
        txtProgTitulo.Text = "Instalando o SigeDash…";
        _saida.Clear();

        var empresa = (txtEmpresa.Text ?? "").Replace("\"", "").Trim();
        var cnpj    = (txtCnpj.Text ?? "").Replace("\"", "").Trim();
        var token   = (txtToken.Text ?? "").Replace("\"", "").Trim();
        var fdb     = (txtFdb.Text ?? "").Replace("\"", "").Trim();

        var args = $"-NoProfile -ExecutionPolicy Bypass -File \"{script}\" " +
                   $"-NomeCliente \"{empresa}\" -Cnpj \"{cnpj}\" -LimiteDispositivos {limite} " +
                   $"-TunnelToken \"{token}\" -FdbPath \"{fdb}\" -Force";

        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = args,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = dir,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };

        try
        {
            _proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
            _proc.OutputDataReceived += (_, e) => { if (e.Data != null) Log(e.Data); };
            _proc.ErrorDataReceived  += (_, e) => { if (e.Data != null) Log(e.Data); };
            _proc.Start();
            _proc.BeginOutputReadLine();
            _proc.BeginErrorReadLine();
            await Task.Run(() => _proc.WaitForExit());

            var code = _proc.ExitCode;
            _instalando = false;
            barProg.IsIndeterminate = false;
            barProg.Value = 100;

            if (code == 0) { MontarConclusao(empresa); IrPara(4); }
            else
            {
                txtProgTitulo.Text = "A instalação encontrou um problema";
                barProg.Foreground = new SolidColorBrush(Color.FromRgb(0xF8, 0x71, 0x71));
                btnCancelar.Content = "Fechar";
                Log("");
                Log($">>> Código de saída: {code}. Revise o log acima ou tente novamente.");
            }
        }
        catch (Exception ex)
        {
            _instalando = false;
            barProg.IsIndeterminate = false;
            Log("ERRO ao iniciar o instalador: " + ex.Message);
        }
    }

    private void Log(string linha)
    {
        _saida.AppendLine(linha);
        Dispatcher.Invoke(() =>
        {
            txtLog.AppendText(linha + "\n");
            txtLog.ScrollToEnd();
        });
    }

    // ── Conclusão: extrai credenciais do log e monta a tela ────────────────────
    private void MontarConclusao(string empresaDigitada)
    {
        var txt = _saida.ToString();
        string? P(string pat)
        {
            var m = Regex.Match(txt, pat, RegexOptions.IgnoreCase);
            return m.Success ? m.Groups[1].Value.Trim() : null;
        }

        var empresa  = !string.IsNullOrWhiteSpace(empresaDigitada) ? empresaDigitada : P(@"Empresa\s*:\s*(.+)");
        var url      = Regex.Match(txt, @"https://[\w\-\.]+\.sigedash\.com\.br", RegexOptions.IgnoreCase).Value;
        var adminKey = P(@"AdminKey\s*:\s*(\S+)");

        // IMPORTANTE: o Login/Senha do ADMIN devem ser lidos DENTRO do bloco "ADMINISTRADOR".
        // Senão o "Senha :" do PostgreSQL (impresso antes, no Passo 1) e capturado por engano.
        string? login = null, senha = null;
        var mAdm = Regex.Match(txt, @"ADMINISTRADOR[\s\S]*?Login\s*:\s*(\S+)[\s\S]*?Senha\s*:\s*(\S+)", RegexOptions.IgnoreCase);
        if (mAdm.Success) { login = mAdm.Groups[1].Value.Trim(); senha = mAdm.Groups[2].Value.Trim(); }
        else { login = P(@"Login\s*:\s*(\S+)"); }

        finishCreds.Children.Clear();
        if (!string.IsNullOrWhiteSpace(empresa))  AddCred("Empresa", empresa!);
        if (!string.IsNullOrWhiteSpace(url))      AddCred("Endereço", url);
        if (!string.IsNullOrWhiteSpace(login))    AddCred("Login do admin", login!);
        if (!string.IsNullOrWhiteSpace(senha))    AddCred("Senha temporária", senha!);
        if (!string.IsNullOrWhiteSpace(adminKey)) AddCred("Chave de administração", adminKey!);

        if (finishCreds.Children.Count == 0)
        {
            txtFinishSub.Text = "Instalação concluída. Confira os dados no log da etapa anterior.";
            AddCred("Status", "Instalado com sucesso");
        }
    }

    private void AddCred(string rotulo, string valor)
    {
        var row = new Grid { Margin = new Thickness(0, 6, 0, 6) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var lbl = new TextBlock
        {
            Text = rotulo, FontSize = 12.5, VerticalAlignment = VerticalAlignment.Center,
            Foreground = new SolidColorBrush(Color.FromRgb(0x94, 0xA3, 0xB8))
        };
        var val = new TextBox
        {
            Text = valor, IsReadOnly = true, BorderThickness = new Thickness(0),
            Background = Brushes.Transparent, FontSize = 13.5, FontWeight = FontWeights.SemiBold,
            Foreground = new SolidColorBrush(Color.FromRgb(0xE2, 0xE8, 0xF0)),
            VerticalContentAlignment = VerticalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            FontFamily = new FontFamily("Consolas"), TextWrapping = TextWrapping.NoWrap
        };
        Grid.SetColumn(val, 1);
        row.Children.Add(lbl);
        row.Children.Add(val);

        // Ícone de copiar (📋) — clique copia a linha e vira ✓ por 1,5s.
        var btn = new Button
        {
            Content = "\U0001F4CB", ToolTip = "Copiar", Width = 34,
            Style = (Style)FindResource("BtnCopy"), VerticalAlignment = VerticalAlignment.Center,
            FontFamily = new FontFamily("Segoe UI Emoji, Segoe UI Symbol"), FontSize = 14
        };
        btn.Click += (_, __) =>
        {
            try
            {
                Clipboard.SetText(valor);
                btn.Content = "✓";
                btn.Foreground = new SolidColorBrush(Color.FromRgb(0x34, 0xD3, 0x99));
                var t = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
                t.Tick += (s, e) => { btn.Content = "\U0001F4CB"; btn.ClearValue(ForegroundProperty); t.Stop(); };
                t.Start();
            }
            catch { }
        };
        Grid.SetColumn(btn, 2);
        row.Children.Add(btn);

        finishCreds.Children.Add(row);
    }
}
