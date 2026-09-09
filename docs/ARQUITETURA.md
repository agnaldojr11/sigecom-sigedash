# Arquitetura do SigeDash BR

> Atualizado em 08/09/2026. Descreve a versão atual do repositório (`main`), com a stack em produção:
> usuários nativos (BCrypt + JWT com sessão única), SigeDash Central (telemetria/frota), auto-update
> in-app, instalador gráfico WPF e licenciamento por dispositivo.

---

## 1. Visão geral

O SigeDash BR coleta indicadores do banco Firebird do ERP **Sigecom** e os exibe em
um Progressive Web App (PWA) acessível pelo celular. Toda a stack roda **no servidor do próprio
cliente**; a SistemasBr acompanha apenas a saúde da frota pela **SigeDash Central** (telemetria sem
dados pessoais). O fluxo completo é:

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         SERVIDOR WINDOWS DO CLIENTE                             │
│                                                                                 │
│  ┌──────────────┐   SQL     ┌──────────────┐   HTTP/JSON    ┌─────────────────┐│
│  │  Firebird 2.5│ ────────► │    Agente    │ ─── gzip ────► │   Backend       ││
│  │  (banco ERP) │           │  .NET FW 4.8 │   /ingest/…    │ ASP.NET Core 8  ││
│  │  SIGECOM     │           │  Win Service │                 │  Win Service    ││
│  └──────────────┘           └──────────────┘                 │                 ││
│                                                               │  PostgreSQL     ││
│                                                               │  (local)        ││
│                                                               └────────┬────────┘│
│                                                                        │          │
│                              Cloudflare Tunnel (gratuito, HTTPS)       │          │
└────────────────────────────────────────────────────────────────────────┼──────────┘
                                                                         │
                                              ┌──────────────────────────▼──────────┐
                                              │            INTERNET                  │
                                              │   https://<tenant>.cloudflareaccess  │
                                              └──────────────────────────┬──────────┘
                                                                         │
                                              ┌──────────────────────────▼──────────┐
                                              │         CELULAR DO DONO              │
                                              │   PWA (HTML/CSS/JS puro)             │
                                              │   Seções: Resumo / Vendas /          │
                                              │           Estoque / Financeiro        │
                                              └──────────────────────────────────────┘
```

**Resumo do fluxo:**

1. O **Agente** executa queries SQL no Firebird (somente leitura) a cada N minutos (cadência por indicador).
2. O resultado é serializado em JSON, comprimido com gzip e enviado via `POST /ingest/{empresa}/{handle}`.
3. O **Backend** autentica o agente pela `X-SigeDash-Key`, descomprime e persiste o snapshot no PostgreSQL (mantendo só o mais recente por indicador).
4. O **PWA** faz login (BCrypt + JWT com sessão única), busca os snapshots via `GET /dash/{empresa}` e renderiza os KPIs.
5. O dono acessa o PWA de qualquer celular via Cloudflare Tunnel (HTTPS, sem porta aberta).
6. O **Backend** envia periodicamente à **SigeDash Central** apenas métricas de saúde (versão, uso, status) — **sem PII**.

---

## 2. Componentes

### 2.1 Agente (`agente/SigeDash.Agente/`)

| Atributo | Valor |
|---|---|
| Plataforma | .NET Framework 4.8, Windows |
| Tipo de processo | Windows Service (`ServiceBase`) |
| Banco lido | Firebird 2.5 via `FirebirdSql.Data.FirebirdClient` |
| Cadencia | Timer de 30 s; cada indicador tem sua propria cadencia em minutos |

**Responsabilidades:**

- Carregar a lista de indicadores do arquivo `indicadores.json`.
- Executar cada query SQL no Firebird (somente leitura) respeitando a cadencia configurada.
- Serializar o resultado em JSON, comprimir em gzip e `POST /ingest/{codigoEmpresa}/{handle}`.

> **Nota:** os usuarios do app deixaram de ser derivados do Firebird. Hoje sao **usuarios nativos**
> do SigeDash (`UsuarioApp`), criados pelo ADM da empresa, com senha em **BCrypt** (ver §5). O agente
> nao le mais senhas do Firebird nem sincroniza a tabela `USUARIO`.

**Componentes internos:**

```
AgenteService.cs         → orquestrador (timer, loop, retry)
Indicadores/
  indicadores.json       → catalogo de indicadores (handle, titulo, tipo, cadencia, arquivo SQL)
  IndicadorRunner.cs     → executa SQL e retorna Snapshot
  sql/                   → queries organizadas por dominio (vendas/, estoque/, financeiro/, saldo/)
Firebird/
  FirebirdReader.cs      → wrapper de leitura do Firebird
Envio/
  BackendClient.cs       → HttpClient reutilizavel, cabecalho X-SigeDash-Key, envio gzip
Config/
  AppConfig.cs           → le sigedash-agente.ini (ChaveCliente, BackendUrl, CodigoEmpresa, etc.)
```

**Tratamento de erros:** em caso de falha no envio de um indicador, a proxima tentativa e agendada para +1 minuto. Se a sincronizacao de usuarios falhar, o retry e em 5 minutos.

---

### 2.2 Backend (`backend/src/SigeDash.Api/`)

| Atributo | Valor |
|---|---|
| Plataforma | ASP.NET Core 8, .NET 8 |
| Banco | PostgreSQL via EF Core 8 + Npgsql (local, scram-sha-256) |
| Autenticacao | JWT Bearer (HS256) com sessao unica; senhas em BCrypt |
| Hospedagem | Windows Service (no servidor do cliente) |
| Exposicao | Cloudflare Tunnel (HTTPS, sem porta aberta) |
| PWA | Servido como arquivos estaticos de `wwwroot/` |
| Seguranca | Headers (CSP/HSTS/nosniff/frame), rate limiting, gate local, telemetria a Central |

**Endpoints (principais):**

| Rota | Metodo | Auth | Descricao |
|---|---|---|---|
| `/auth/empresas` | GET | Nenhuma | Lista clientes ativos (popula dropdown do login) |
| `/auth/login` | POST | Nenhuma | Autentica usuario (BCrypt), retorna JWT + `sid`; aplica lockout |
| `/auth/trocar-senha` | POST | JWT | Troca de senha (obrigatoria no primeiro acesso) |
| `/auth/sessao` | GET | JWT | Valida o token/sessao atual |
| `/ingest/{empresa}/{handle}` | POST | `X-SigeDash-Key` | Recebe snapshot gzip de um indicador |
| `/dash/{empresa}` | GET | JWT | Retorna todos os snapshots mais recentes da empresa |
| `/ia/query` | POST | JWT | Consulta ao assistente IA (OpenAI-compatible) com contexto dos snapshots |
| `/admin/usuarios` (+ `/{id}`, `/permissoes`, `/resetar-senha`) | GET/POST/PUT/DELETE | JWT (admin) | Gestao de usuarios e permissoes pelo ADM da empresa |
| `/admin/plano` | GET | JWT (admin) | Limite de dispositivos e uso atual |
| `/admin/atualizacao/status` · `/aplicar` | GET · POST | JWT (admin) | Auto-update in-app (ver §9) |
| `/admin/clientes` | GET/POST | `X-Admin-Key` | Provisionamento de clientes (uso interno SistemasBr) |
| `/admin/limite-dispositivos` · `/reset-senha` | POST | `X-Admin-Key` | Operacoes internas (licenca, reset) |

> Endpoints com papel de admin **relem `EhAdmin` no banco** a cada chamada (não confiam só no claim);
> operacoes sensiveis tem **gate local** (bloqueadas fora da rede do servidor). Chaves `X-Admin-Key` /
> `X-Telemetria-Key` sao comparadas em **tempo constante** (`FixedTimeEquals`).

**Modelo de dados (essencial):**

```
Cliente
  Id, Nome, ChaveApi, Ativo, LimiteDispositivos (0 = ilimitado)
  └── Loja (1-N)
        Id, ClienteId, CodigoEmpresa, Nome

UsuarioApp                          ← usuario NATIVO do SigeDash
  Id, ClienteId, Login, SenhaHash (BCrypt)
  EhAdmin, PrimeiroAcesso, Permissoes
  SessaoToken (sid da sessao ativa) ← sessao unica
  TentativasFalhas, BloqueadoAte    ← lockout
  TotpSecret, TotpAtivado           ← estrutura 2FA (roadmap)

Snapshot                            ← so o mais recente por (cliente, empresa, indicador)
  Id, ClienteId, CodigoEmpresa, IndicadorHandle
  PayloadJson, GeradoEm, RecebidoEm
```

**Startup:**
- Migrations sao aplicadas automaticamente no inicio, com **retry** aguardando o PostgreSQL subir
  (evita o boot-race que derrubava o servico → 502 no Cloudflare).
- O `SeedData`/instalador cria o cliente e o usuario **admin inicial** com senha temporaria
  (troca obrigatoria no primeiro login).
- Em desenvolvimento, o `WebRoot` aponta para `../../../pwa/` (fonte) para hot-reload sem build step.
- Em producao (publish), a pasta `pwa/` e copiada para `wwwroot/` pelo `.csproj`.
- Servicos hospedados: **telemetria** (heartbeat a Central) e **retencao** (expurgo de snapshots antigos).

---

### 2.3 PWA (`pwa/`)

| Atributo | Valor |
|---|---|
| Stack | HTML5 + CSS3 + JavaScript puro (sem framework, sem build step) |
| Graficos | Chart.js 4.4 (via CDN no `index.html`) |
| Instalavel | `manifest.webmanifest` + Service Worker (`service-worker.js`) |
| Tema | Dark mode, bottom navigation, mobile-first |

**Estrutura de arquivos:**

```
pwa/
  index.html           → shell unico; inclui login e todas as secoes
  css/app.css          → estilos (dark mode, KPI cards, bottom nav)
  js/
    api.js             → modulo API (fetch + token JWT em sessionStorage)
    app.js             → navegacao, renderizacao das secoes (Resumo/Vendas/Estoque/Financeiro)
    render.js          → funcoes de renderizacao de cards, rankings, graficos
  service-worker.js    → cache offline (network-first para API, cache-first para assets)
  manifest.webmanifest → metadados PWA (nome, icones, cor de tema)
```

**Secoes do app:**

| Secao | Conteudo |
|---|---|
| Resumo | KPIs principais do dia (vendas, pedidos, ticket medio, resumo financeiro) |
| Vendas | Rankings, pico horario, formas de pagamento, custo x venda |
| Estoque | Top 10, abaixo do minimo, itens zerados, pesquisa de produto |
| Financeiro | Contas a receber/pagar por periodo, inadimplencia, vencimentos proximos, saldos |

**Assistente IA:** botao FAB que abre um overlay de chat. Envia a pergunta do usuario junto com os snapshots atuais para `POST /ia/query` e exibe a resposta em linguagem natural.

---

## 3. Fluxo de dados

### 3.1 Coleta e envio (Agente → Backend)

```
[Timer 30s]
    │
    ├─► Para cada indicador vencido:
    │       1. IndicadorRunner le arquivo SQL de indicadores/sql/
    │       2. FirebirdReader.Consultar() → executa no Firebird
    │       3. Resultado serializado como JSON
    │       4. Comprimido com GZip → MemoryStream
    │       5. POST /ingest/{codigoEmpresa}/{handle}
    │          Header: X-SigeDash-Key: <chave>
    │          Header: Content-Encoding: gzip
    │       6. Backend descomprime, insere Snapshot no PostgreSQL (substitui o anterior do mesmo indicador)
```

> Os **usuarios do app sao nativos** (`UsuarioApp`, senha BCrypt), criados pelo ADM da empresa — o
> agente nao sincroniza mais usuarios nem le senhas do Firebird.

### 3.2 Exibicao (PWA)

```
[Usuario abre o PWA]
    │
    ├─► GET /auth/empresas → popula <select> de empresa
    ├─► POST /auth/login   → BCrypt.Verify(senha, SenhaHash)
    │                        gera JWT com `sid`, grava `sid` em UsuarioApp.SessaoToken
    │                        (login novo derruba a sessao anterior); salvo em sessionStorage
    │
    └─► GET /dash/{empresa}
            │
            ├─► Retorna array de snapshots mais recentes por handle
            ├─► app.js distribui snapshots por secao
            └─► render.js renderiza cards, rankings, bar charts (Chart.js)

[Auto-refresh a cada 5 minutos]
    └─► GET /dash/{empresa} novamente
```

---

## 4. Indicadores disponíveis

Total: **26 indicadores**, organizados em 4 dominios.

### Vendas (11 indicadores)

| Handle | Titulo | Tipo | Cadencia |
|---|---|---|---|
| `vendas_total_hoje` | Total de vendas hoje | info | 2 min |
| `vendas_qtd_pedidos` | Pedidos hoje | info | 2 min |
| `vendas_ticket_medio` | Ticket medio hoje | info | 2 min |
| `vendas_total_semana` | Total de vendas na semana | info | 15 min |
| `vendas_total_mes` | Total de vendas do mes | info | 15 min |
| `vendas_top_produtos` | Top 5 produtos do mes | ranking | 15 min |
| `vendas_pico_horario` | Pico de vendas por horario | bar | 30 min |
| `vendas_top_clientes` | Top 5 clientes do mes | ranking | 30 min |
| `vendas_top_vendedores` | Top 5 vendedores do mes | ranking | 30 min |
| `vendas_forma_pagamento` | Formas de pagamento — mes | ranking | 30 min |
| `vendas_custo_venda` | Custo x Venda — mes | list | 60 min |

### Estoque (4 indicadores)

| Handle | Titulo | Tipo | Cadencia |
|---|---|---|---|
| `estoque_sem_estoque` | Itens zerados | info | 30 min |
| `estoque_abaixo_min` | Abaixo do minimo | ranking | 30 min |
| `estoque_pesquisa_produto` | Pesquisa de produtos | ranking | 30 min |
| `estoque_top_produtos` | Top 10 em estoque | ranking | 60 min |

### Financeiro (9 indicadores)

| Handle | Titulo | Tipo | Cadencia |
|---|---|---|---|
| `financeiro_receber_hoje` | Contas a receber hoje | info | 15 min |
| `financeiro_pagar_hoje` | Contas a pagar hoje | info | 15 min |
| `receber_por_cliente` | Contas a receber por cliente | ranking | 15 min |
| `financeiro_receber_semana` | Contas a receber esta semana | info | 30 min |
| `financeiro_pagar_semana` | Contas a pagar esta semana | info | 30 min |
| `financeiro_receber_mes` | Contas a receber este mes | info | 30 min |
| `financeiro_pagar_mes` | Contas a pagar este mes | info | 30 min |
| `financeiro_inadimplencia` | Inadimplencia total | info | 30 min |
| `financeiro_vencimentos_proximos` | A pagar — proximos 7 dias | ranking | 30 min |

### Saldo (2 indicadores)

| Handle | Titulo | Tipo | Cadencia |
|---|---|---|---|
| `saldo_caixas` | Saldo dos caixas | list | 15 min |
| `saldo_bancario` | Saldo bancario | list | 30 min |

**Tipos de indicador:**

| Tipo | Renderizacao no PWA |
|---|---|
| `info` | KPI card com valor numerico/monetario principal |
| `ranking` | Lista ordenada com posicao, nome e valor |
| `bar` | Grafico de barras (Chart.js) |
| `list` | Lista de itens com multiplos campos |

---

## 5. Autenticação e autorização

Detalhes completos e a postura de seguranca do produto estao em [`SEGURANCA.md`](SEGURANCA.md).
Resumo dos mecanismos:

### 5.1 Autenticacao do Agente (chave de API)

```
Agente → Backend
  Header: X-SigeDash-Key: <ChaveApi do cliente>
```

- A chave fica no config do agente (no servidor do cliente) e valida contra `Cliente.ChaveApi`.
- Usada em: `POST /ingest/{empresa}/{handle}`.

### 5.2 Autenticacao do Usuario (BCrypt + JWT com sessao unica)

```
PWA → Backend
  1. POST /auth/login  { cliente, login, senha }
     ├─ BCrypt.Verify(senha, UsuarioApp.SenhaHash)   (fator 12)
     ├─ Lockout: apos N tentativas erradas, bloqueia por um tempo (TentativasFalhas/BloqueadoAte)
     ├─ Gera JWT HS256; grava o `sid` do token em UsuarioApp.SessaoToken (SESSAO UNICA)
     └─ Se PrimeiroAcesso, exige troca de senha (/auth/trocar-senha)

  2. Requisicoes autenticadas:
     Header: Authorization: Bearer <token>
     Claims: cliente_id, usuario_id, admin, sid, name
     ├─ Middleware compara `sid` do token com UsuarioApp.SessaoToken → 401 se divergente
     │  (login em outro dispositivo derruba o anterior — last-login-wins)
     └─ Isolamento por `cliente_id`: cada consulta filtra pelo cliente do token
```

- JWT em `sessionStorage` (limpo ao fechar a aba), assinado com `Jwt:SecretKey` (HS256, algoritmo
  travado na validacao).
- **Permissoes por usuario:** cada usuario ve so as secoes liberadas pelo ADM (trava no backend e na UI).
- **Papel de admin revalidado no banco** (`EhAdmin`) a cada operacao sensivel.
- **Licenciamento por dispositivo:** `Cliente.LimiteDispositivos` (0 = ilimitado) trava criacao de
  usuarios acima do limite contratado.

### 5.3 Autenticacao Admin/interno (chave)

```
Operacoes internas SistemasBr → Backend
  Header: X-Admin-Key: <AdminKey do appsettings>   (comparada em tempo constante)
  Rotas: /admin/clientes, /admin/limite-dispositivos, /admin/reset-senha
```

Usada para provisionar clientes e operacoes de suporte. As rotas `/admin/usuarios*`, `/admin/plano` e
`/admin/atualizacao/*` sao do **ADM da empresa** (autenticacao JWT, nao a chave interna).

---

## 6. Configuração

### 6.1 Backend — `appsettings.json`

```json
{
  "ConnectionStrings": {
    "Postgres": "Host=localhost;Port=5432;Database=sigedash;Username=sigedash;Password=TROCAR"
  },
  "Jwt": {
    "Issuer": "sigedash",
    "Audience": "sigedash-pwa",
    "SecretKey": "TROCAR-POR-CHAVE-LONGA-ALEATORIA-32+CHARS"
  },
  "AdminKey": "TROCAR-POR-CHAVE-ADMIN-FORTE",
  "AllowedOrigins": [ "https://dash.sigedash.com.br" ]
}
```

| Chave | Descricao | Obrigatorio |
|---|---|---|
| `ConnectionStrings:Postgres` | String de conexao PostgreSQL | Sim |
| `Jwt:SecretKey` | Chave HMAC para assinar JWTs (minimo 32 chars) | Sim |
| `Jwt:Issuer` | Identificador do emissor do token | Sim |
| `Jwt:Audience` | Audiencia esperada do token | Sim |
| `AdminKey` | Chave para endpoints `/admin/*` | Sim |
| `AllowedOrigins` | Origens CORS permitidas | So em dev |

**Sobrescrita local (sem git):** criar `appsettings.Development.local.json` ou
`appsettings.Production.local.json` com os valores reais. Esses arquivos estao no `.gitignore`.

### 6.2 Agente — `sigedash-agente.ini`

O arquivo e gerado pelo instalador (`configurar-cliente.ps1`, chamado por `instalar-agente.ps1`).

| Chave | Descricao |
|---|---|
| `BackendUrl` | URL do backend (ex.: `https://<tunnel>.trycloudflare.com`) |
| `ChaveCliente` | `ChaveApi` gerada pelo backend para este cliente |
| `CodigoEmpresa` | `CODIGOEMPRESA` do Sigecom (geralmente `1` para matriz) |
| `FirebirdConnectionString` | String de conexao com o banco Firebird do Sigecom |

---

## 7. Build e publish

### 7.1 Backend

```bash
# Publicar para Windows x64 (auto-contido)
dotnet publish backend/src/SigeDash.Api/SigeDash.Api.csproj \
  -c Release \
  -r win-x64 \
  --self-contained true \
  -o publish/backend

# O diretorio publish/backend/ contem:
#   SigeDash.Api.exe      → executavel unico
#   wwwroot/              → PWA copiado automaticamente pelo .csproj
#   appsettings.json      → configuracoes base (sem segredos)
```

O `.csproj` inclui automaticamente `pwa/**/*` como conteudo de `wwwroot/` no publish:

```xml
<Content Include="..\..\..\pwa\**\*" Link="wwwroot\%(RecursiveDir)%(Filename)%(Extension)">
  <CopyToPublishDirectory>PreserveNewest</CopyToPublishDirectory>
</Content>
```

### 7.2 Agente

```bash
# Publicar binarios .NET 4.8 (win-x64, framework-dependent)
dotnet publish agente/SigeDash.Agente/SigeDash.Agente.csproj \
  -c Release -r win-x64 --self-contained false -o publish/agente
```

No cliente, `instalar-agente.ps1` (nao-interativo) copia esses binarios, chama
`configurar-cliente.ps1` para gerar o config e registrar o servico Windows `SigeDashAgente`.
O build do pacote (`build-deploy.ps1`) ja faz o publish do agente para a subpasta `agente/`
automaticamente — nao ha mais instalador InnoSetup.

### 7.3 Desenvolvimento local

```bash
# Iniciar backend (porta 5000) — aponta WebRoot para ../../../pwa/ automaticamente
cd backend/src/SigeDash.Api
dotnet run

# Ou via script na raiz do repo:
.\iniciar-backend.ps1
```

O PWA e acessado em `http://localhost:5000` em desenvolvimento. O `api.js` detecta `localhost`
e usa `http://localhost:5000` como `BASE`, evitando necessidade de CORS.

### 7.4 Migrations EF Core

```bash
# Criar nova migration
cd backend/src/SigeDash.Api
dotnet ef migrations add <NomeDaMigration>

# Aplicar manualmente (a aplicacao tambem aplica no startup)
dotnet ef database update
```

---

## 8. Estrutura de pastas

```
sigedash-br/
│
├── agente/
│   └── SigeDash.Agente/
│       ├── AgenteService.cs          ← orquestrador Windows Service
│       ├── Config/AppConfig.cs       ← leitura do .ini
│       ├── Envio/BackendClient.cs    ← HTTP para o backend
│       ├── Firebird/FirebirdReader.cs← queries no Firebird
│       ├── Indicadores/
│       │   ├── indicadores.json      ← catalogo de indicadores
│       │   ├── IndicadorRunner.cs    ← executa SQL + serializa
│       │   └── sql/                  ← queries por dominio
│       │       ├── vendas/           (11 arquivos .sql)
│       │       ├── estoque/          (4 arquivos .sql)
│       │       ├── financeiro/       (9 arquivos .sql)
│       │       └── saldo/            (2 arquivos .sql)
│       └── Program.cs                ← entrada (modo service ou console)
│
├── backend/
│   └── src/SigeDash.Api/
│       ├── Program.cs                ← startup, middlewares, migrations
│       ├── appsettings.json          ← configuracoes base (sem segredos)
│       ├── Data/
│       │   ├── AppDbContext.cs       ← EF Core DbContext
│       │   └── SeedData.cs          ← seed de desenvolvimento
│       ├── Endpoints/
│       │   ├── AuthEndpoints.cs      ← /auth/login, /auth/empresas
│       │   ├── IngestEndpoints.cs    ← /ingest/...
│       │   ├── DashEndpoints.cs      ← /dash/...
│       │   ├── IaEndpoints.cs        ← /ia/query
│       │   └── AdminEndpoints.cs     ← /admin/clientes
│       ├── Modelos/Entidades.cs      ← Cliente, Loja, UsuarioApp, Snapshot
│       └── Migrations/               ← EF Core migrations
│
├── pwa/
│   ├── index.html                    ← shell unico (login + app)
│   ├── css/app.css                   ← estilos dark mode, KPI cards
│   ├── js/
│   │   ├── api.js                    ← fetch wrapper + JWT
│   │   ├── app.js                    ← navegacao + renderizacao das secoes
│   │   └── render.js                 ← cards, rankings, charts
│   ├── service-worker.js             ← cache offline
│   └── manifest.webmanifest          ← metadados PWA
│
├── central/
│   └── SigeDash.Central/             ← telemetria + painel da frota (.NET 8 + PG, Railway)
│       ├── Program.cs                ← DATABASE_URL, fail-fast JWT, rate limit, headers, seed
│       ├── Endpoints/               (Telemetria / Painel / AdminCentral)
│       ├── Servicos/RetencaoHostedService.cs   ← expurgo do historico
│       ├── wwwroot/                 ← painel (login + dashboard da frota)
│       └── Dockerfile · README-RAILWAY.md
│
├── installer/
│   └── SigeDash.Installer/           ← wizard grafico WPF (.NET 8, self-contained)
│       ├── MainWindow.xaml(.cs)      ← 4 etapas, roda instalar-tudo.ps1, mostra credenciais
│       └── app.manifest              ← requireAdministrator
│
├── deploy/
│   ├── agente/
│   │   └── configurar-cliente.ps1    ← gera config e registra servico Windows
│   └── backend/
│       ├── instalar-tudo.ps1         ← orquestrador (chamado pelo wizard/tecnico)
│       ├── instalar-agente.ps1       ← instala binarios + servico do agente
│       ├── instalar-backend.ps1      ← registra backend + tarefa SigeDash-Aplicar
│       ├── instalar-postgres.ps1     ← instala PostgreSQL
│       ├── instalar-tunnel.ps1       ← instala Cloudflare Tunnel
│       └── atualizar.ps1             ← auto-update (verifica Authenticode)
│
├── docs/
│   ├── ARQUITETURA.md                ← este documento
│   └── SEGURANCA.md                  ← postura de seguranca e LGPD
│
├── build-deploy.ps1                  ← publica backend/agente/wizard + gera os 2 zips
└── iniciar-backend.ps1               ← atalho para dev local
```

---

## 9. SigeDash Central (telemetria + painel da frota)

Servico independente (`central/SigeDash.Central`, .NET 8 + PostgreSQL) hospedado na **Railway**. Recebe
o phone-home dos backends dos clientes e serve o painel de monitoramento da frota para a SistemasBr.

- **Telemetria (phone-home):** o backend de cada cliente envia um heartbeat periodico
  (`TelemetriaHostedService`, ~3 min) com **apenas** versao, uso e status/saude dos indicadores —
  **nenhum dado pessoal ou de venda**. Autenticado por `X-Telemetria-Key` (gerada por CSPRNG, prefixo `SGT-`).
- **Painel:** login proprio (com lockout), visao da frota (`/painel/frota`) e detalhe por cliente —
  quem esta online, em que versao, se os indicadores sincronizam.
- **Provisionamento interno:** `/admin/clientes` protegido por `X-Admin-Key` (tempo constante).
- **Hardening:** JWT com fail-fast (nao sobe com chave fraca), rate limiting (login/admin/telemetria),
  headers de seguranca (CSP/HSTS/nosniff/frame), truncamento/cap na telemetria, retencao/expurgo do
  historico (`RetencaoHostedService`, `Retencao:HistoricoDias`).

## 10. Atualizacao automatica (auto-update in-app)

O admin da empresa atualiza o cliente pelo painel, sem tecnico presencial:

- `GET /admin/atualizacao/status` compara o `version.txt` local com a ultima release do GitHub
  (cache, tolerante a offline). O PWA mostra um **banner "Atualizar agora"** (so admin).
- `POST /admin/atualizacao/aplicar` dispara a tarefa agendada **SYSTEM** `SigeDash-Aplicar`, que roda o
  `atualizar.ps1` independentemente do backend (permite auto-sobrescrever).
- O `atualizar.ps1` baixa o pacote **enxuto** (`SigeDash-Deploy-v*.zip`), **verifica a assinatura
  Authenticode** dos executaveis (assinante deve conter `SISTEMASBR`, senao aborta — A-03), para os
  servicos, copia preservando os configs e reinicia. Ha tambem a tarefa semanal como fallback.

## 11. Instalador grafico (wizard WPF)

`installer/SigeDash.Installer` — aplicativo WPF (.NET 8, self-contained single-file, roda em Windows
limpo sem runtime) com a identidade do SigeDash (4 etapas: Bem-vindo / Configuracao / Instalacao /
Concluido). Coleta empresa/FDB/dispositivos/token, roda o `instalar-tudo.ps1` por baixo (streaming do
log + barra) e mostra as credenciais finais (login/senha do admin, AdminKey, URL) com botao de copiar.
Eleva via `app.manifest`. Substitui o antigo launcher de console.

**Empacotamento (2 pacotes):** `SigeDash-Deploy-vX.zip` (enxuto, sem o wizard → usado pelo auto-update)
e `SigeDash-Instalador-vX.zip` (com o wizard → instalacao de cliente novo). Os executaveis sao
assinados (EV DigiCert) antes da distribuicao.

---

## Referencia rapida de endpoints

```
# Sem autenticacao
GET  /auth/empresas                → lista clientes ativos
POST /auth/login                   → { cliente, login, senha } → { token, cliente, sid }

# Autenticado (JWT)
POST /auth/trocar-senha            → troca de senha (obrigatoria no 1o acesso)
GET  /auth/sessao                  → valida token/sessao
GET  /dash/{empresa}               → todos os snapshots mais recentes
POST /ia/query                     → { pergunta, contexto } → resposta IA

# ADM da empresa (JWT admin)
GET/POST/PUT/DELETE /admin/usuarios[...]      → gestao de usuarios e permissoes
GET  /admin/plano                             → limite de dispositivos e uso
GET  /admin/atualizacao/status                → ha nova versao?
POST /admin/atualizacao/aplicar               → dispara o auto-update

# Agente (X-SigeDash-Key)
POST /ingest/{empresa}/{handle}    → snapshot gzip de um indicador

# Interno SistemasBr (X-Admin-Key, tempo constante)
GET/POST /admin/clientes           → provisiona clientes / retorna ChaveApi
POST /admin/limite-dispositivos    → define a licenca por dispositivo
POST /admin/reset-senha            → reset de senha (suporte)

# SigeDash Central (servico separado, Railway)
POST /telemetria/heartbeat         → (X-Telemetria-Key) metricas de saude, sem PII
POST /painel/login · GET /painel/frota · /painel/clientes/{id}   → painel da frota
```
