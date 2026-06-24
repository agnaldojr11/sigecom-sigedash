# Arquitetura do SigeDash BR

> Documento gerado em 22/06/2026. Descreve a versão atual do repositório (`main`).

---

## 1. Visão geral

O SigeDash BR coleta indicadores do banco Firebird do ERP **Sigecom** e os exibe em
um Progressive Web App (PWA) acessível pelo celular. O fluxo completo é:

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

1. O **Agente** executa queries SQL no Firebird a cada N minutos (cadência por indicador).
2. O resultado é serializado em JSON, comprimido com gzip e enviado via `POST /ingest/{empresa}/{handle}`.
3. O **Backend** autentica o agente pela `X-SigeDash-Key`, descomprime e persiste o snapshot no PostgreSQL.
4. O **PWA** faz login com JWT, busca os snapshots via `GET /dash/{empresa}` e renderiza os KPIs.
5. O dono acessa o PWA de qualquer celular via Cloudflare Tunnel (HTTPS gratuito).

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
- Executar cada query SQL no Firebird respeitando a cadencia configurada.
- Serializar o resultado em JSON, comprimir em gzip e `POST /ingest/{codigoEmpresa}/{handle}`.
- Sincronizar usuarios do Firebird (tabela `USUARIO`) para o backend a cada 1 hora via `POST /ingest/usuarios`.
- Decodificar a senha proprietaria do Sigecom (`enc[p*4] - 10 - p`) e reencripta-la como SHA-1 hex antes de enviar.

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
| Banco | PostgreSQL via EF Core 8 + Npgsql |
| Autenticacao | JWT Bearer (HMAC-SHA256) |
| Hospedagem | Windows Service ou Linux (systemd) |
| PWA | Servido como arquivos estaticos de `wwwroot/` |

**Endpoints:**

| Rota | Metodo | Auth | Descricao |
|---|---|---|---|
| `/auth/empresas` | GET | Nenhuma | Lista clientes ativos (popula dropdown do login) |
| `/auth/login` | POST | Nenhuma | Autentica usuario, retorna JWT (8 h) |
| `/ingest/usuarios` | POST | `X-SigeDash-Key` | Sincroniza usuarios do Firebird |
| `/ingest/{empresa}/{handle}` | POST | `X-SigeDash-Key` | Recebe snapshot gzip de um indicador |
| `/dash/{empresa}` | GET | JWT Bearer | Retorna todos os snapshots mais recentes da empresa |
| `/ia/query` | POST | JWT Bearer | Consulta ao assistente IA com contexto dos snapshots |
| `/admin/clientes` | GET/POST | `X-Admin-Key` | Gerencia clientes (uso interno SistemasBr) |

**Modelo de dados:**

```
Cliente
  Id, Nome, ChaveApi, Ativo
  └── Loja (1-N)
        Id, ClienteId, CodigoEmpresa, Nome

UsuarioApp
  Id, ClienteId, Login, SenhaApp (SHA-1 hex)

Snapshot
  Id, ClienteId, CodigoEmpresa, IndicadorHandle
  PayloadJson, GeradoEm, RecebidoEm
```

**Startup:**
- Migrations sao aplicadas automaticamente no inicio (`db.Database.Migrate()`).
- Em ambiente `Development`, o `SeedData` cria o cliente "5 Estrelas" com `ChaveApi = "TESTE-5ESTRELAS-0001"` se o banco estiver vazio.
- Em desenvolvimento, o `WebRoot` aponta para `../../../pwa/` (fonte) para hot-reload sem build step.
- Em producao (publish), a pasta `pwa/` e copiada para `wwwroot/` pelo `.csproj`.

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
    │       6. Backend descomprime, insere Snapshot no PostgreSQL
    │
    └─► A cada 1 hora (e no startup):
            1. SELECT LOGIN, SENHA FROM USUARIO WHERE DESATIVADO = 'N'
            2. Decodifica senha proprietaria Sigecom
            3. Recalcula SHA-1 hex
            4. POST /ingest/usuarios → backend upserta UsuarioApp
```

**Nota sobre senhas:** o Sigecom armazena senhas com codificacao proprietaria. O agente decodifica
(`byte = enc[p*4] - 10 - p`), reaplica SHA-1, e envia o hash para o backend. O backend compara
esse hash no login.

### 3.2 Exibicao (PWA)

```
[Usuario abre o PWA]
    │
    ├─► GET /auth/empresas → popula <select> de empresa
    ├─► POST /auth/login   → retorna JWT (8 h), salvo em sessionStorage
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

## 5. Autenticação

O sistema usa dois mecanismos de autenticacao distintos:

### 5.1 Autenticacao do Agente (chave de API)

```
Agente → Backend
  Header: X-SigeDash-Key: <ChaveApi do cliente>

Geracao da chave: <NOME_CLIENTE_12CHARS>-<ANO>-<8 chars UUID>
  Exemplo: "5ESTRELAS-2025-A1B2C3D4"
```

- A chave fica em `sigedash-agente.ini` (no servidor do cliente).
- O backend valida contra `Cliente.ChaveApi` no PostgreSQL.
- Usada em: `POST /ingest/usuarios` e `POST /ingest/{empresa}/{handle}`.

### 5.2 Autenticacao do Usuario (JWT)

```
PWA → Backend
  1. POST /auth/login  { cliente, login, senha }
     ├─ Backend verifica: SHA1(senha) == UsuarioApp.SenhaApp
     └─ Retorna JWT (HMAC-SHA256, validade 8 h)

  2. Requisicoes autenticadas:
     Header: Authorization: Bearer <token>
     Token claims: cliente_id (int), name (login)
```

- O JWT e guardado em `sessionStorage` (limpo ao fechar a aba).
- O token tem duracao de **8 horas**.
- Algoritmo de assinatura: `HMAC-SHA256` com chave simetrica (`Jwt:SecretKey`).

### 5.3 Autenticacao Admin

```
Operacoes admin → Backend
  Header: X-Admin-Key: <AdminKey do appsettings>
  Rotas: GET /admin/clientes, POST /admin/clientes
```

Usada pela equipe SistemasBr para cadastrar novos clientes no backend.

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
├── deploy/
│   ├── agente/
│   │   └── configurar-cliente.ps1    ← gera config e registra servico Windows
│   └── backend/
│       ├── instalar-tudo.ps1         ← orquestrador (executado pelo tecnico)
│       ├── instalar-agente.ps1       ← instala binarios + servico do agente
│       ├── instalar-backend.ps1      ← registra backend como Windows Service
│       ├── instalar-postgres.ps1     ← instala PostgreSQL
│       └── instalar-tunnel.ps1       ← instala Cloudflare Tunnel
│
├── docs/
│   └── ARQUITETURA.md                ← este documento
│
└── iniciar-backend.ps1               ← atalho para dev local
```

---

## Referencia rapida de endpoints

```
# Sem autenticacao
GET  /auth/empresas                → lista clientes ativos
POST /auth/login                   → { cliente, login, senha } → { token, cliente }

# Agente (X-SigeDash-Key)
POST /ingest/usuarios              → sincroniza usuarios do Firebird
POST /ingest/{empresa}/{handle}    → snapshot gzip de um indicador

# PWA (Bearer JWT)
GET  /dash/{empresa}               → todos os snapshots mais recentes
POST /ia/query                     → { pergunta, contexto } → resposta IA

# Admin (X-Admin-Key)
GET  /admin/clientes               → lista clientes
POST /admin/clientes               → cadastra novo cliente, retorna ChaveApi
```
