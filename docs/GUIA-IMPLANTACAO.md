# SigeDash — Guia de Implantação

**Versão:** 1.0 · **Equipe:** Suporte / Implementação SistemasBr  
**Público:** Técnicos que instalam o SigeDash em clientes novos e atualizações

---

## Visão Geral da Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│  SERVIDOR DO CLIENTE (Windows, on-premise)                  │
│                                                             │
│  ┌──────────────────────────────────────────────┐          │
│  │  SigeDash Agente (Windows Service)           │          │
│  │  • Lê o Firebird do SIGECOM (somente leitura)│          │
│  │  • Envia snapshots via HTTPS a cada 10-30min │          │
│  └──────────────────────────────────────────────┘          │
│           │ HTTPS POST (X-SigeDash-Key)                     │
└───────────┼─────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────────────────────────────────────────┐
│  VPS SISTEMASBR (Linux, Docker)                             │
│                                                             │
│  nginx (HTTPS/443) → Backend .NET 8 → PostgreSQL            │
│                          │                                  │
│                     Serve o PWA                             │
│                   (dash.sigedash.com.br)                    │
└─────────────────────────────────────────────────────────────┘
            │ HTTPS (JWT)
            ▼
┌─────────────────────────────────────────────────────────────┐
│  CELULAR / BROWSER DO USUÁRIO                               │
│  PWA instalável — funciona como app nativo                  │
└─────────────────────────────────────────────────────────────┘
```

**O que precisa ser instalado em cada cliente:** apenas o **SigeDash Agente** (um arquivo `.exe`).  
O painel web (PWA) roda no servidor da SistemasBr — o cliente só precisa abrir o link no celular.

---

## Parte 1 — Servidor da SistemasBr (VPS)

> Esta etapa é feita **uma única vez** pela equipe de TI interna.  
> Após configurada, o VPS atende todos os clientes automaticamente.

### Pré-requisitos do VPS

| Requisito | Versão mínima |
|---|---|
| SO | Ubuntu 22.04 LTS (ou Debian 12) |
| Docker | 24+ |
| Docker Compose | Plugin v2 (`docker compose`) |
| DNS | `dash.sigedash.com.br` apontando para o IP do VPS |
| Portas abertas | 80 (HTTP), 443 (HTTPS) |

### 1.1 Clonar o repositório

```bash
git clone https://github.com/sistemasbr/sigecom-sigedash.git /opt/sigedash
cd /opt/sigedash
```

### 1.2 Configurar variáveis de ambiente

```bash
cp .env.example .env
nano .env
```

Edite os valores marcados com `TROCAR_`:

```env
POSTGRES_PASSWORD=SENHA_FORTE_AQUI
ConnectionStrings__Postgres=Host=db;Port=5432;Database=sigedash;Username=sigedash;Password=SENHA_FORTE_AQUI
Jwt__SecretKey=CHAVE_ALEATORIA_MINIMO_32_CHARS
```

Para gerar uma chave JWT segura:
```bash
openssl rand -base64 48
```

### 1.3 Obter certificado SSL (Let's Encrypt — gratuito)

```bash
# Instala certbot
apt install -y certbot

# Gera o certificado (porta 80 deve estar livre)
certbot certonly --standalone -d dash.sigedash.com.br \
  --agree-tos -m suporte@sistemasbr.net

# Copia os certs para a pasta do nginx
mkdir -p /opt/sigedash/nginx/certs
cp /etc/letsencrypt/live/dash.sigedash.com.br/fullchain.pem /opt/sigedash/nginx/certs/
cp /etc/letsencrypt/live/dash.sigedash.com.br/privkey.pem  /opt/sigedash/nginx/certs/
```

Renovação automática (adicionar ao crontab):
```bash
# crontab -e
0 3 * * * certbot renew --quiet && \
  cp /etc/letsencrypt/live/dash.sigedash.com.br/*.pem /opt/sigedash/nginx/certs/ && \
  docker compose -f /opt/sigedash/docker-compose.yml restart nginx
```

### 1.4 Subir os serviços

```bash
cd /opt/sigedash
docker compose up -d
```

Verificar se está rodando:
```bash
docker compose ps
# Deve mostrar: sigedash-backend, sigedash-db, sigedash-nginx — todos "Up"
```

Testar:
```bash
curl -k https://dash.sigedash.com.br/auth/login
# Deve retornar erro JSON (não 404), confirmando que o backend responde
```

### 1.5 Cadastrar o cliente no sistema

Use a API para criar o cliente e gerar a chave:

```bash
# Substituir com os dados reais
curl -X POST https://dash.sigedash.com.br/admin/clientes \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: CHAVE_ADMIN" \
  -d '{
    "nome": "5 Estrelas Autopeças",
    "chaveApi": "5ESTRELAS-2024-XXXX",
    "codigoEmpresa": 1
  }'
```

> A `chaveApi` gerada aqui será informada ao técnico que instalará o agente no cliente.

### 1.6 Criar usuário do painel para o cliente

```bash
curl -X POST https://dash.sigedash.com.br/admin/usuarios \
  -H "Content-Type: application/json" \
  -H "X-Admin-Key: CHAVE_ADMIN" \
  -d '{
    "clienteNome": "5 Estrelas Autopeças",
    "login": "gerente",
    "senha": "Senha@2024",
    "departamento": "gerencia"
  }'
```

---

## Parte 2 — Instalação no Servidor do Cliente

> Esta etapa é feita pelo técnico de suporte **em cada novo cliente**.  
> Tempo estimado: **10 a 15 minutos**.

### Pré-requisitos no servidor do cliente

| Requisito | Observação |
|---|---|
| Windows Server 2012 R2+ ou Windows 10+ | x64 |
| .NET Framework 4.8 Runtime | Já instalado se o SIGECOM estiver rodando |
| Firebird Server 2.5+ rodando | Banco do SIGECOM deve estar acessível |
| Acesso à internet (HTTPS saída) | Para enviar dados ao VPS |

Verificar se o .NET 4.8 está instalado:
```
Win + R → appwiz.cpl → Microsoft .NET Framework 4.8
```
Se não estiver: [download.microsoft.com — .NET Framework 4.8](https://dotnet.microsoft.com/download/dotnet-framework/net48)

### 2.1 Informações necessárias antes de começar

Levante estas informações com o cliente antes de ir ao servidor:

| Dado | Onde encontrar | Exemplo |
|---|---|---|
| Caminho do banco Firebird | Configuração do SIGECOM | `C:\Sigecom\dados\EMPRESA.FDB` |
| Senha do SYSDBA | DBA / implantador do SIGECOM | geralmente `masterkey` |
| Chave do cliente | SistemasBr (gerada no passo 1.5) | `5ESTRELAS-2024-XXXX` |

### 2.2 Executar o instalador

1. Copie o arquivo **`SigeDashAgente-Setup-vX.X.X.exe`** para o servidor do cliente  
   *(disponível em `\\servidor-sistemasbr\releases\sigedash\` ou link de download)*

2. **Execute como Administrador** (clique com botão direito → "Executar como administrador")

3. Siga o assistente:
   - Clique **Avançar** nas telas iniciais
   - Na tela **"Configuração da Conexão"**, preencha:

   | Campo | Valor |
   |---|---|
   | Caminho do banco Firebird | `C:\Sigecom\dados\EMPRESA.FDB` *(caminho real)* |
   | URL do Backend SigeDash | `https://dash.sigedash.com.br` |
   | Chave do Cliente | Chave fornecida pela SistemasBr |

4. Clique **Avançar** → **Instalar**

5. O instalador irá automaticamente:
   - Copiar os arquivos para `C:\Program Files\SistemasBr\SigeDash\`
   - Gravar o arquivo de configuração
   - Registrar e iniciar o **Windows Service**

### 2.3 Verificar se o serviço está rodando

```
Win + R → services.msc
Procurar: "SigeDash Agente"
Status deve ser: "Em execução"
```

Ou via PowerShell:
```powershell
Get-Service SigeDashAgente
```

### 2.4 Verificar os logs do agente

Os logs ficam em:
```
C:\Program Files\SistemasBr\SigeDash\logs\agente.log
```

Primeiros logs esperados (em ~30 segundos):
```
[INFO] Agente iniciando. Cliente=5ESTRELAS-2024-XXXX Empresa=1
[INFO] Indicador OK: vendas_total_hoje
[INFO] Indicador OK: vendas_total_mes
...
```

Se aparecer erro `Connection refused` ou `Unauthorized`:
- Verifique a URL do backend e a chave do cliente no arquivo de config
- Veja a seção "Solução de Problemas" abaixo

### 2.5 Testar o painel

1. No celular ou computador do cliente, abra: **https://dash.sigedash.com.br**
2. Faça login com as credenciais criadas no passo 1.6
3. Aguarde até 2 minutos para os primeiros dados aparecerem
4. Instale como PWA:
   - **Android/Chrome:** menu ⋮ → "Adicionar à tela inicial"
   - **iOS/Safari:** botão compartilhar → "Adicionar à Tela de Início"

---

## Parte 3 — Atualização do Agente

Para atualizar o agente em um cliente existente:

1. Execute o novo **`SigeDashAgente-Setup-vX.X.X.exe`** como Administrador
2. O instalador detecta a versão anterior, para o serviço, substitui os arquivos e reinicia
3. **As configurações do cliente são preservadas** (o instalador não sobrescreve `agente.config.json` existente)

> Se precisar alterar alguma configuração, edite manualmente:  
> `C:\Program Files\SistemasBr\SigeDash\Config\agente.config.json`  
> E reinicie o serviço: `services.msc` → SigeDash Agente → Reiniciar

---

## Parte 4 — Atualização do Backend (VPS)

```bash
cd /opt/sigedash
git pull
docker compose build --no-cache backend
docker compose up -d backend
```

O banco de dados é preservado no volume Docker `pgdata`. Migrations novas são aplicadas automaticamente na inicialização.

---

## Solução de Problemas

### Agente não inicia (serviço em estado "Parado")

1. Verifique os logs: `C:\Program Files\SistemasBr\SigeDash\logs\agente.log`
2. Erros comuns:

| Erro no log | Causa | Solução |
|---|---|---|
| `Unable to open database` | Caminho do .FDB errado ou Firebird offline | Verificar caminho e se o serviço Firebird está rodando |
| `Connection refused` | Backend inacessível | Verificar URL e se o VPS está online |
| `Unauthorized (401)` | Chave do cliente inválida | Verificar a chave em `agente.config.json` e no servidor |
| `Invalid data source` | Senha SYSDBA incorreta | Verificar password na connection string |

Para editar a configuração:
```
C:\Program Files\SistemasBr\SigeDash\Config\agente.config.json
```

Depois de editar, reinicie o serviço:
```
services.msc → SigeDash Agente → Reiniciar
```

### Dados não aparecem no painel

1. Verifique se o agente está rodando (`services.msc`)
2. Verifique se há erros no log do agente
3. Aguarde até 30 segundos (cadência mínima dos indicadores)
4. No painel, clique no botão **↻ Atualizar** no topo

### Painel abre mas mostra tela em branco

1. Limpe o cache do browser: `Ctrl+Shift+R`
2. Se instalado como PWA, desinstale e reinstale (o service worker pode estar com cache antigo)

### Serviço não aparece em `services.msc`

Execute como Administrador:
```cmd
sc create SigeDashAgente binPath= "C:\Program Files\SistemasBr\SigeDash\SigeDash.Agente.exe" start= auto DisplayName= "SigeDash Agente"
sc start SigeDashAgente
```

---

## Referência Rápida

| Ação | Comando / Local |
|---|---|
| Verificar serviço | `services.msc` → SigeDash Agente |
| Logs do agente | `C:\Program Files\SistemasBr\SigeDash\logs\agente.log` |
| Config do agente | `C:\Program Files\SistemasBr\SigeDash\Config\agente.config.json` |
| Reiniciar serviço | `services.msc` → clique direito → Reiniciar |
| Parar serviço | `sc stop SigeDashAgente` |
| Iniciar serviço | `sc start SigeDashAgente` |
| Ver logs VPS | `docker compose logs -f backend` |
| Reiniciar backend | `docker compose restart backend` |
| URL do painel | https://dash.sigedash.com.br |

---

*SistemasBr — Suporte: suporte@sistemasbr.net*
