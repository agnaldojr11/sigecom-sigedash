# SigeDash — Guia de Instalação em Novo Cliente

**Versão:** 1.0 · **Público:** Técnicos SistemasBr · **Idioma:** pt-BR

---

## Visão geral

O SigeDash roda inteiramente **no servidor Windows do cliente**. Nenhum dado sai para a nuvem — o Cloudflare Tunnel só cria um túnel HTTPS para que o cliente acesse o painel pelo celular, sem expor a porta diretamente.

```
Firebird 2.5 (Sigecom)
        ↓ lê a cada X minutos
  SigeDash Agente (Windows Service)
        ↓ envia snapshots via HTTP
  SigeDash Backend API (Windows Service, porta 5000)
        ↑ PWA busca dados aqui
  Cloudflare Tunnel (HTTPS público)
        ↑ cliente acessa pelo celular
```

**Tempo estimado de instalação:** 45–60 minutos

---

## Checklist pré-instalação

Verifique tudo antes de começar. Se algum item estiver pendente, resolva antes de prosseguir.

- [ ] Servidor Windows 10/11 Pro ou Windows Server 2016+
- [ ] Sigecom instalado e funcionando
- [ ] Firebird 2.5 instalado e o serviço `FirebirdServerDefaultInstance` está rodando
- [ ] Caminho do banco `.FDB` do cliente anotado (ex.: `C:\Sigecom\dados\EMPRESA.FDB`)
- [ ] Senha do `SYSDBA` do Firebird anotada (padrão: `masterkey`)
- [ ] Acesso de Administrador no servidor
- [ ] Internet ativa no servidor
- [ ] Você possui a **AdminKey** do SigeDash (fornecida pela SistemasBr)

> **Dica:** Para descobrir o caminho do `.FDB`, abra o Sigecom, vá em **Configurações → Banco de Dados** ou pergunte ao administrador do cliente.

---

## Passo 1 — Instalar PostgreSQL 16

O SigeDash usa PostgreSQL como banco de dados interno (armazena snapshots dos indicadores).

### 1.1 — Download

- [ ] Acesse: **https://www.postgresql.org/download/windows/**
- [ ] Clique em **Download the installer** (EDB installer)
- [ ] Selecione a versão **16.x** e o instalador **Windows x86-64**
- [ ] Salve o arquivo (ex.: `postgresql-16.x-windows-x64.exe`)

[SCREENSHOT: Página de download do PostgreSQL, selecionando versão 16 e Windows x86-64]

### 1.2 — Instalação

- [ ] Execute o instalador **como Administrador** (botão direito → "Executar como administrador")
- [ ] Clique **Next** nas telas iniciais
- [ ] **Installation Directory:** mantenha o padrão (`C:\Program Files\PostgreSQL\16`)
- [ ] **Select Components:** marque apenas **PostgreSQL Server** e **Command Line Tools** (desmarque pgAdmin e Stack Builder para agilizar)
- [ ] **Data Directory:** mantenha o padrão
- [ ] **Password:** defina a senha do superusuário `postgres`. **Anote esta senha!**
- [ ] **Port:** mantenha **5432**
- [ ] **Locale:** mantenha o padrão
- [ ] Clique **Next** → **Next** → **Install**
- [ ] Ao finalizar, **desmarque** "Launch Stack Builder" e clique **Finish**

[SCREENSHOT: Tela de senha do PostgreSQL durante instalação]

### 1.3 — Criar banco e usuário do SigeDash

- [ ] Abra o **Prompt de Comando como Administrador**
- [ ] Execute os comandos abaixo, um por vez:

```cmd
cd "C:\Program Files\PostgreSQL\16\bin"
```

```cmd
psql -U postgres -c "CREATE USER sigedash WITH PASSWORD 'SigeDash@2024!';"
```

```cmd
psql -U postgres -c "CREATE DATABASE sigedash OWNER sigedash;"
```

```cmd
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE sigedash TO sigedash;"
```

> Quando solicitado, informe a senha do `postgres` que você definiu na instalação.

- [ ] Verifique que funcionou:

```cmd
psql -U sigedash -d sigedash -c "SELECT version();"
```

Se aparecer a versão do PostgreSQL, o banco está funcionando corretamente.

[SCREENSHOT: Prompt de comando mostrando o resultado de SELECT version()]

> **Senha padrão usada neste guia:** `SigeDash@2024!`
> Se preferir usar uma senha diferente, anote-a pois será necessária na configuração do backend.

---

## Passo 2 — Instalar SigeDash Backend

O Backend é uma API .NET 8 que também serve o PWA (painel web). Ele roda como Windows Service na porta 5000.

### 2.1 — Criar a pasta e copiar os arquivos

- [ ] Crie a pasta de instalação:

```cmd
mkdir C:\SigeDash\Backend
```

- [ ] Copie todos os arquivos do pacote `SigeDashBackend-vX.X.zip` para `C:\SigeDash\Backend\`
- [ ] Confirme que o arquivo `SigeDash.Api.exe` está em `C:\SigeDash\Backend\SigeDash.Api.exe`

[SCREENSHOT: Pasta C:\SigeDash\Backend com os arquivos descompactados]

### 2.2 — Criar o arquivo de configuração de produção

- [ ] Abra o **Bloco de Notas** como Administrador
- [ ] Crie o arquivo `C:\SigeDash\Backend\appsettings.Production.json` com o conteúdo abaixo:

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=localhost;Port=5432;Database=sigedash;Username=sigedash;Password=SigeDash@2024!"
  },
  "Jwt": {
    "Issuer": "sigedash",
    "Audience": "sigedash-pwa",
    "SecretKey": "SUBSTITUIR-POR-CHAVE-GERADA-NO-PASSO-ABAIXO"
  },
  "AdminKey": "SUBSTITUIR-POR-CHAVE-ADMIN-FORTE",
  "AllowedOrigins": [ "https://SUBSTITUIR-PELO-TUNNEL-URL.trycloudflare.com" ],
  "AllowedHosts": "*",
  "Logging": { "LogLevel": { "Default": "Warning" } }
}
```

> **ATENÇÃO:** Os campos marcados com `SUBSTITUIR` **precisam ser alterados** antes de continuar. Veja as instruções abaixo.

### 2.3 — Gerar a chave JWT

A chave JWT protege o login dos usuários. Deve ter pelo menos 32 caracteres aleatórios.

- [ ] Abra o **PowerShell** e execute:

```powershell
-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 48 | ForEach-Object { [char]$_ })
```

- [ ] Copie o resultado (ex.: `kR7mXpQ2wNvAjB9cLsE4hGfUoYtD6iZr3nWqP8xVC0Ky`) e cole no campo `SecretKey` do arquivo JSON

### 2.4 — Definir a AdminKey

A AdminKey protege os endpoints de administração. Use uma sequência longa e aleatória.

- [ ] No PowerShell, execute novamente o mesmo comando do passo 2.3 para gerar outra chave
- [ ] Cole no campo `AdminKey` do arquivo JSON
- [ ] **Anote a AdminKey** — você precisará dela no Passo 3 e no Passo 5

> O campo `AllowedOrigins` será preenchido depois que o Cloudflare Tunnel for configurado no Passo 4. Por enquanto, deixe o placeholder.

### 2.5 — Instalar como Windows Service

- [ ] Abra o **Prompt de Comando como Administrador**
- [ ] Execute:

```cmd
sc.exe create SigeDashBackend binPath= "C:\SigeDash\Backend\SigeDash.Api.exe" start= auto DisplayName= "SigeDash Backend"
```

```cmd
sc.exe description SigeDashBackend "API e painel web do SigeDash"
```

```cmd
sc.exe start SigeDashBackend
```

- [ ] Verifique se o serviço iniciou:

```cmd
sc.exe query SigeDashBackend
```

O campo `STATE` deve mostrar `RUNNING`.

[SCREENSHOT: Resultado de sc.exe query SigeDashBackend mostrando STATE: RUNNING]

### 2.6 — Testar o backend

- [ ] Abra o navegador no servidor e acesse: **http://localhost:5000/health**
- [ ] Deve aparecer a resposta: `{"status":"ok",...}`

> Se o navegador não carregar, verifique os logs em:
> `C:\SigeDash\Backend\logs\` ou no Visualizador de Eventos do Windows (procure por "SigeDash").

---

## Passo 3 — Instalar SigeDash Agente

O Agente é o Windows Service que lê os dados do Firebird (Sigecom) e os envia ao backend local.

### 3.1 — Instalação automática (sem assistente)

O agente **não tem mais instalador interativo**. Ele é instalado automaticamente pelo
`instalar-tudo.ps1` (Passo 1), junto com backend, PostgreSQL e tunnel. Esta seção é apenas
para reinstalar/atualizar **somente o agente**, quando necessário.

- [ ] No PowerShell **como Administrador**, dentro da pasta do pacote, execute:

```powershell
.\instalar-agente.ps1 `
    -AdminKey "SUA_ADMIN_KEY" `
    -ClienteNome "NOME DO CLIENTE" `
    -FdbPath "C:\Sigecom\dados\EMPRESA.FDB"
```

- [ ] O script automaticamente:
  - Copia os binários para `C:\Program Files\SistemasBr\SigeDash\`
  - Registra o cliente no backend (usando a `AdminKey`)
  - Grava o arquivo de configuração `Config\agente.config.json`
  - Instala e inicia o serviço Windows `SigeDashAgente`

> A `AdminKey` é a chave gerada no Passo 2.4. `BackendUrl` assume `http://localhost:5000`
> por padrão (agente e backend ficam no mesmo servidor).

- [ ] Se aparecer erro "não foi possível registrar o cliente":
  - Verifique se o backend está rodando: `sc.exe query SigeDashBackend`
  - Verifique o log em: `C:\Program Files\SistemasBr\SigeDash\Config\setup.log`
  - Consulte a seção **Solução de Problemas** no final deste guia

### 3.5 — Verificar o serviço do agente

- [ ] No Prompt de Comando (Administrador):

```cmd
sc.exe query SigeDashAgente
```

O campo `STATE` deve mostrar `RUNNING`.

- [ ] Verifique os primeiros logs do agente:

```cmd
type "C:\Program Files\SistemasBr\SigeDash\Config\setup.log"
```

Procure pela linha `=== Configuração concluída! ===` e `ChaveApi: ...`.

---

## Passo 4 — Configurar Cloudflare Tunnel

O Cloudflare Tunnel cria um endereço HTTPS público e seguro para o painel, sem precisar abrir portas no roteador do cliente.

### 4.1 — Criar conta Cloudflare (gratuita)

- [ ] Acesse **https://dash.cloudflare.com/sign-up** e crie uma conta gratuita
- [ ] Confirme o e-mail

> A conta gratuita é suficiente para o uso do SigeDash.

### 4.2 — Baixar o cloudflared

- [ ] Acesse: **https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/**
- [ ] Baixe o arquivo **cloudflared-windows-amd64.exe**
- [ ] Renomeie para `cloudflared.exe` e mova para `C:\SigeDash\cloudflared.exe`

[SCREENSHOT: Página de download do cloudflared, destacando o link Windows x86-64]

### 4.3 — Autenticar no Cloudflare

- [ ] Abra o **Prompt de Comando como Administrador**
- [ ] Execute:

```cmd
C:\SigeDash\cloudflared.exe tunnel login
```

- [ ] O navegador será aberto automaticamente — faça login na conta Cloudflare criada
- [ ] Autorize o acesso. Após autorizado, feche o navegador

[SCREENSHOT: Navegador mostrando página de autorização do Cloudflare Tunnel]

### 4.4 — Criar o túnel

- [ ] No Prompt de Comando (ainda como Administrador), execute:

```cmd
C:\SigeDash\cloudflared.exe tunnel create sigedash-NOMECLIENTE
```

Substitua `NOMECLIENTE` por um identificador do cliente (ex.: `sigedash-autopecassilva`).

- [ ] Anote o **Tunnel ID** exibido no resultado (formato: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

### 4.5 — Criar arquivo de configuração do túnel

- [ ] Crie a pasta:

```cmd
mkdir C:\SigeDash\tunnel
```

- [ ] Crie o arquivo `C:\SigeDash\tunnel\config.yml` com o Bloco de Notas:

```yaml
tunnel: SUBSTITUIR-PELO-TUNNEL-ID
credentials-file: C:\Users\SEU-USUARIO\.cloudflared\TUNNEL-ID.json

ingress:
  - service: http://localhost:5000
```

Substitua `TUNNEL-ID` pelo ID anotado no passo anterior e `SEU-USUARIO` pelo nome do usuário Windows atual.

### 4.6 — Gerar URL pública e instalar como serviço

- [ ] Execute para criar uma URL temporária e testar:

```cmd
C:\SigeDash\cloudflared.exe tunnel --config C:\SigeDash\tunnel\config.yml run
```

- [ ] Anote a URL gerada (ex.: `https://xxxx-yyyy.trycloudflare.com`)
- [ ] Pressione **Ctrl+C** para parar o processo temporário

> **Alternativa mais simples (sem conta):** Use o modo rápido `cloudflared.exe tunnel --url http://localhost:5000`. Isso gera uma URL temporária imediatamente, sem precisar criar conta. A URL muda a cada reinicialização — adequado para testes, mas não para produção.

- [ ] Instale o túnel como serviço Windows:

```cmd
C:\SigeDash\cloudflared.exe service install
```

```cmd
net start cloudflared
```

[SCREENSHOT: Terminal mostrando o URL gerado pelo Cloudflare Tunnel]

### 4.7 — Atualizar AllowedOrigins no backend

Agora que você tem a URL do túnel, atualize o arquivo de configuração do backend:

- [ ] Abra `C:\SigeDash\Backend\appsettings.Production.json`
- [ ] Substitua o placeholder em `AllowedOrigins` pela URL real do túnel:

```json
"AllowedOrigins": [ "https://xxxx-yyyy.trycloudflare.com" ]
```

- [ ] Reinicie o serviço do backend:

```cmd
sc.exe stop SigeDashBackend
sc.exe start SigeDashBackend
```

---

## Passo 5 — Criar o usuário do cliente

Após tudo instalado, crie o primeiro usuário para o cliente acessar o painel.

> Os usuários do Sigecom são sincronizados automaticamente pelo agente quando ele inicia. Após alguns minutos o agente pode ter criado os usuários automaticamente. Verifique antes de criar manualmente.

### 5.1 — Verificar se os usuários já foram sincronizados

- [ ] Abra o PowerShell e execute:

```powershell
Invoke-RestMethod -Uri "http://localhost:5000/admin/clientes" `
  -Headers @{ "X-Admin-Key" = "SUA-ADMIN-KEY-AQUI" }
```

Substitua `SUA-ADMIN-KEY-AQUI` pela AdminKey definida no Passo 2.4.

Se o cliente aparecer na lista com `chaveApi` preenchida, o registro foi feito automaticamente pelo instalador.

### 5.2 — Criar cliente manualmente (se necessário)

Se o cliente não aparecer na lista ou o instalador não conseguiu registrar:

- [ ] Execute no PowerShell:

```powershell
$body = @{
    nome          = "Nome do Cliente"
    codigoEmpresa = 1
    nomeLoja      = "Matriz"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5000/admin/clientes" `
  -Method POST `
  -Headers @{ "X-Admin-Key" = "SUA-ADMIN-KEY-AQUI"; "Content-Type" = "application/json" } `
  -Body $body
```

Substitua `"Nome do Cliente"` pelo nome real da empresa.

- [ ] O retorno incluirá a `chaveApi` — **anote essa chave**

### 5.3 — Acessar o painel

- [ ] Abra o navegador (no servidor ou no celular) e acesse a URL do Cloudflare Tunnel
- [ ] A tela de login do SigeDash será exibida
- [ ] Os usuários sincronizados do Sigecom podem fazer login com suas credenciais do sistema

[SCREENSHOT: Tela de login do SigeDash no navegador]

---

## Verificação final

Percorra esta lista após completar todos os passos:

### Backend

- [ ] `sc.exe query SigeDashBackend` mostra `STATE: RUNNING`
- [ ] `http://localhost:5000/health` responde no navegador do servidor
- [ ] URL do Cloudflare Tunnel abre o painel no celular

### Agente

- [ ] `sc.exe query SigeDashAgente` mostra `STATE: RUNNING`
- [ ] Log em `C:\Program Files\SistemasBr\SigeDash\Config\setup.log` mostra `=== Configuração concluída! ===`
- [ ] Aguardar 5 minutos e verificar se os indicadores aparecem no painel

### Indicadores disponíveis

O SigeDash mostrará automaticamente os seguintes indicadores após sincronização:

| Seção | Indicadores |
|---|---|
| Vendas | Total do mês, da semana e de hoje · Pedidos hoje · Ticket médio · Pico por horário · Top clientes/produtos/vendedores · Formas de pagamento · Custo × Venda |
| Estoque | Top 10 em estoque · Abaixo do mínimo · Itens zerados · Pesquisa de produto |
| Financeiro | Contas a receber (mês/semana/hoje) · Contas a pagar (mês/semana/hoje) · Inadimplência · Vencimentos próximos · A receber por cliente |
| Saldo | Saldo dos caixas · Saldo bancário |

### Checklist de entrega ao cliente

- [ ] URL do painel anotada e testada no celular do cliente
- [ ] Login de pelo menos um usuário testado
- [ ] Dados reais aparecendo nos indicadores (aguardar 15 minutos após iniciar o agente)
- [ ] AdminKey guardada em local seguro pela SistemasBr (não compartilhar com o cliente)
- [ ] Instruções de acesso repassadas ao responsável do cliente

---

## Solução de problemas comuns

### Backend não inicia (serviço fica em STOPPED)

**Sintoma:** `sc.exe query SigeDashBackend` mostra `STATE: STOPPED` logo após iniciar.

**Diagnóstico:**
```cmd
eventvwr.msc
```
Vá em **Logs do Windows → Aplicativo** e procure erros com fonte `SigeDashBackend`.

**Causas comuns:**
- PostgreSQL não está rodando → verifique: `sc.exe query postgresql-x64-16`
- Senha do banco incorreta no `appsettings.Production.json`
- Porta 5000 em uso por outro processo: `netstat -ano | findstr :5000`

---

### Agente não consegue conectar ao Firebird

**Sintoma:** Log do agente mostra erros de conexão com o banco Firebird.

**Verificações:**
- [ ] O serviço Firebird está rodando: `sc.exe query FirebirdServerDefaultInstance`
- [ ] O caminho do `.FDB` está correto e o arquivo existe
- [ ] A senha do SYSDBA está correta (padrão: `masterkey`)
- [ ] Tente conectar manualmente com o isql do Firebird:

```cmd
"C:\Program Files\Firebird\Firebird_2_5\bin\isql.exe" -user SYSDBA -password masterkey "C:\Sigecom\dados\EMPRESA.FDB"
```

---

### Instalador do agente mostra aviso de "não foi possível registrar"

**Sintoma:** Durante a instalação do agente, aparece aviso de que o registro automático falhou.

**Verificações:**
- [ ] Backend está rodando: `sc.exe query SigeDashBackend`
- [ ] URL informada no instalador era `http://localhost:5000` (sem barra no final)
- [ ] AdminKey informada no instalador é idêntica à do `appsettings.Production.json`
- [ ] Verifique o log: `type "C:\Program Files\SistemasBr\SigeDash\Config\setup.log"`

**Solução manual:** Após corrigir o problema, execute o script de configuração manualmente:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "C:\Program Files\SistemasBr\SigeDash\configurar-cliente.ps1" `
  -BackendUrl "http://localhost:5000" `
  -AdminKey "SUA-ADMIN-KEY" `
  -ClienteNome "Nome do Cliente" `
  -FdbPath "C:\Sigecom\dados\EMPRESA.FDB"
```

---

### Painel não abre pelo celular

**Sintoma:** URL do Cloudflare abre página de erro ou não carrega.

**Verificações:**
- [ ] Serviço cloudflared está rodando: `sc.exe query cloudflared`
- [ ] Backend está rodando na porta 5000: `http://localhost:5000/health`
- [ ] A URL em `AllowedOrigins` no `appsettings.Production.json` está correta

**Reiniciar o túnel:**
```cmd
net stop cloudflared
net start cloudflared
```

---

### Indicadores aparecem mas mostram valores zerados ou antigos

**Sintoma:** Painel carrega, mas os números estão zerados ou desatualizados.

**Verificações:**
- [ ] Aguarde pelo menos 15–30 minutos após a primeira instalação (o agente precisa coletar os dados)
- [ ] Verifique se o agente está rodando: `sc.exe query SigeDashAgente`
- [ ] Verifique se o banco Sigecom tem movimento (teste uma venda de R$ 0,01 se necessário)
- [ ] Veja os logs do agente no Visualizador de Eventos do Windows

---

### Firewall bloqueando comunicação interna

**Sintoma:** Agente não consegue enviar dados para o backend mesmo estando no mesmo servidor.

**Solução:** Adicione regra de firewall para a porta 5000:

```cmd
netsh advfirewall firewall add rule name="SigeDash Backend" dir=in action=allow protocol=TCP localport=5000
```

---

## Informações de referência

| Item | Valor padrão |
|---|---|
| Porta do backend | 5000 |
| Banco de dados | `sigedash` (PostgreSQL local) |
| Usuário PostgreSQL | `sigedash` |
| Nome do serviço backend | `SigeDashBackend` |
| Nome do serviço agente | `SigeDashAgente` |
| Pasta do backend | `C:\SigeDash\Backend\` |
| Pasta do agente | `C:\Program Files\SistemasBr\SigeDash\` |
| Config do agente | `...\Config\agente.config.json` |
| Log de instalação | `...\Config\setup.log` |

---

*Guia mantido pela equipe SistemasBr. Dúvidas: agnaldo@sistemasbr.net*
