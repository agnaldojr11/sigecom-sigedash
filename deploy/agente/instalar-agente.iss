; ── SigeDash Agente — Script de Instalação (Inno Setup 6.x) ─────────────────────
; Gera: SigeDashAgente-Setup.exe
; Requer: binários compilados em deploy\agente\bin\ (gerados por build-instalador.bat)
; Instala o agente como Windows Service (auto-start) e grava a config informada pelo técnico.
; ────────────────────────────────────────────────────────────────────────────────

#define AppName      "SigeDash Agente"
; Versão pode ser injetada pelo CI/CD: ISCC.exe /dAppVersion=1.2.3 instalar-agente.iss
; Se não informada, usa o fallback abaixo.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppPublisher "SistemasBr"
#define AppExe       "SigeDash.Agente.exe"
#define ServiceName  "SigeDashAgente"
#define ServiceLabel "SigeDash Agente"
#define InstallDir   "{autopf}\SistemasBr\SigeDash"

[Setup]
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppId={{A3F7C2D1-8E4B-4F0A-9C6D-2B5E8F1A3C7D}
DefaultDirName={#InstallDir}
DefaultGroupName=SistemasBr\SigeDash
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=SigeDashAgente-Setup-v{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
CloseApplications=yes
RestartIfNeededByRun=no
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExe}
; Ícone do instalador (opcional — descomente se tiver um .ico)
; SetupIconFile=..\..\Logo-BG\icon.ico

[Languages]
Name: "ptbr"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Files]
; Binários compilados do agente (Release x64)
Source: "bin\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\Desinstalar {#AppName}"; Filename: "{uninstallexe}"

; ── Páginas customizadas e lógica de configuração ────────────────────────────
[Code]

var
  PageConfig: TInputQueryWizardPage;

// ── Cria a página de configuração do agente ──────────────────────────────────
procedure InitializeWizard;
begin
  PageConfig := CreateInputQueryPage(wpSelectDir,
    'Configuração da Conexão',
    'Informe os dados necessários para o agente se conectar',
    'O técnico deve preencher com os dados do cliente. As informações serão' +
    ' gravadas no arquivo de configuração do agente.');

  // Campo 0: caminho do arquivo .FDB do Firebird
  PageConfig.Add('Caminho do banco de dados Firebird (.FDB):', False);
  PageConfig.Values[0] := 'C:\Sigecom\dados\EMPRESA.FDB';

  // Campo 1: URL do backend SigeDash (VPS)
  PageConfig.Add('URL do Backend SigeDash:', False);
  PageConfig.Values[1] := 'https://dash.sigedash.com.br';

  // Campo 2: chave única do cliente (fornecida pela SistemasBr)
  PageConfig.Add('Chave do Cliente (fornecida pela SistemasBr):', False);
  PageConfig.Values[2] := '';
end;

// ── Valida campos antes de prosseguir ────────────────────────────────────────
function NextButtonClick(CurPageID: Integer): Boolean;
var
  fdb, url, chave: String;
begin
  Result := True;
  if CurPageID = PageConfig.ID then
  begin
    fdb   := Trim(PageConfig.Values[0]);
    url   := Trim(PageConfig.Values[1]);
    chave := Trim(PageConfig.Values[2]);

    if fdb = '' then
    begin
      MsgBox('Por favor, informe o caminho do banco Firebird (.FDB).', mbError, MB_OK);
      Result := False; Exit;
    end;
    if url = '' then
    begin
      MsgBox('Por favor, informe a URL do Backend SigeDash.', mbError, MB_OK);
      Result := False; Exit;
    end;
    if chave = '' then
    begin
      MsgBox('Por favor, informe a Chave do Cliente fornecida pela SistemasBr.', mbError, MB_OK);
      Result := False; Exit;
    end;
  end;
end;

// ── Gera agente.config.json com os valores informados ────────────────────────
procedure GravarConfig;
var
  fdb, url, chave: String;
  connStr, json: String;
  configPath: String;
  lines: TStringList;
begin
  fdb   := Trim(PageConfig.Values[0]);
  url   := Trim(PageConfig.Values[1]);
  chave := Trim(PageConfig.Values[2]);

  // Escapa barras invertidas para JSON
  StringChangeEx(fdb, '\', '\\', True);

  connStr := 'User=SYSDBA;Password=masterkey;Database=' + fdb +
             ';DataSource=localhost;Port=3050;Dialect=3;Charset=ISO8859_1;' +
             'Pooling=true;ConnectionLifetime=60';

  json :=
    '{' + #13#10 +
    '  "FirebirdConnectionString": "' + connStr + '",' + #13#10 +
    '  "CodigoEmpresa": 1,' + #13#10 +
    '  "BackendUrl": "' + url + '",' + #13#10 +
    '  "ChaveCliente": "' + chave + '",' + #13#10 +
    '  "PastaSql": "Indicadores/sql"' + #13#10 +
    '}';

  configPath := ExpandConstant('{app}\Config\agente.config.json');

  lines := TStringList.Create;
  try
    lines.Text := json;
    lines.SaveToFile(configPath);
  finally
    lines.Free;
  end;
end;

// ── Para o serviço se já existir (atualização) ───────────────────────────────
procedure PararServico;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop {#ServiceName}',
    '', SW_HIDE, ewWaitUntilTerminated, nil);
  // Pequena pausa para o SCM registrar a parada
  Sleep(1500);
end;

// ── Remove instalação anterior do serviço ────────────────────────────────────
procedure RemoverServico;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'delete {#ServiceName}',
    '', SW_HIDE, ewWaitUntilTerminated, nil);
  Sleep(500);
end;

// ── Registra e inicia o Windows Service ──────────────────────────────────────
procedure InstalarServico;
var
  exePath, params: String;
  resultCode: Integer;
begin
  exePath := ExpandConstant('{app}\{#AppExe}');

  // sc create
  params := 'create {#ServiceName} binPath= "' + exePath + '"' +
            ' start= auto DisplayName= "{#ServiceLabel}"';
  Exec(ExpandConstant('{sys}\sc.exe'), params, '', SW_HIDE,
    ewWaitUntilTerminated, @resultCode);

  // Descrição do serviço
  Exec(ExpandConstant('{sys}\sc.exe'),
    'description {#ServiceName} "Sincroniza dados do Firebird com o painel SigeDash"',
    '', SW_HIDE, ewWaitUntilTerminated, @resultCode);

  // sc start
  Exec(ExpandConstant('{sys}\sc.exe'), 'start {#ServiceName}',
    '', SW_HIDE, ewWaitUntilTerminated, @resultCode);
end;

// ── Hook pós-instalação dos arquivos ─────────────────────────────────────────
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    GravarConfig;
    PararServico;    // garante que não há instância antiga rodando
    RemoverServico;  // remove registro antigo (atualização)
    InstalarServico; // registra e inicia
  end;
end;

// ── Desinstalação: para e remove o serviço ───────────────────────────────────
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    PararServico;
    RemoverServico;
  end;
end;
