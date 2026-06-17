# SigeDash BR — Arquitetura (Fase 1)

> Objetivo: substituir o SigeDash (Tecnospeed/PlugMobile) por solução própria, eliminando o
> custo mensal. Fase 1 = **paridade funcional** com os indicadores atuais, SQLs reescritos e
> otimizados por nós. Fase 2 = novos relatórios de decisão + pré-venda mobile.

## Visão geral

```
┌─────────────────────────────┐
│  Firebird 2.5 do cliente    │   (mesmo servidor do SIGECOM 32-bit)
└──────────────┬──────────────┘
               │ read-only, DataReader streaming, charset ISO8859_1
┌──────────────▼──────────────┐
│  AGENTE  (.NET Framework 4.8, Windows Service, x64)          │
│  - roda indicadores agendados (cada um com sua cadência)     │
│  - serializa snapshot em JSON, comprime (gzip)               │
└──────────────┬──────────────┘
               │ HTTPS POST  (Authorization: chave do cliente)
┌──────────────▼──────────────┐
│  BACKEND  (ASP.NET Core .NET 8 + PostgreSQL, VPS)            │
│  - /ingest: recebe e guarda snapshot por cliente/loja        │
│  - /auth:   login do usuário do app                          │
│  - /dash:   entrega dashboards prontos ao PWA                │
│  - /admin:  painel de implantação (substitui admin.plugmobile)│
└──────────────┬──────────────┘
               │ HTTPS  (JWT do usuário do app)
┌──────────────▼──────────────┐
│  PWA  (Vanilla JS + Chart.js)                                │
│  - login por cliente, lista de dashboards, gráficos          │
│  - instalável, offline do último snapshot                    │
└─────────────────────────────┘
```

## Por que esse desenho

- **Agente fora do SIGECOM** → zero impacto no monólito 32-bit. Processo separado, 64-bit, só leitura.
- **Snapshot, não consulta ao vivo** → o PWA nunca toca no Firebird do cliente. O backend serve dados já calculados. Protege o banco do cliente e dá resposta instantânea no celular.
- **Backend é quem cresce** → na Fase 2 o canal agente↔backend vira bidirecional (pré-venda desce do backend pro agente, que grava no SIGECOM).

## Decisões de stack (14/06/2026)

| Camada | Escolha | Motivo |
|---|---|---|
| Agente | .NET Framework 4.8, x64 | Presente em todo Windows 7 SP1+/Server 2008 R2+. Sem runtime para instalar. Base de clientes antiga. |
| Driver FB | FirebirdSql.Data.FirebirdClient | Maduro, suporta FB 2.5, controle fino de conexão/charset. |
| Backend | ASP.NET Core (.NET 8) + EF Core Npgsql | Roda no nosso VPS (não no cliente), então pode ser moderno. |
| Banco backend | PostgreSQL | Multi-cliente, snapshots, escala melhor que SQLite. |
| PWA | Vanilla JS + Chart.js | Sem build step, leve, fácil de manter. Alinhado com "sem hype". |

## Restrições herdadas do ecossistema (do CLAUDE.md)

- **Charset Latin1.** O Firebird do cliente devolve ISO-8859-1. O agente **deve** abrir a conexão
  com `Charset=ISO8859_1` e converter para UTF-8 ao montar o JSON. Sem isso, acento quebra no PWA.
- **Firebird 2.5** — sem CTE recursiva, sem window function, sem JSON nativo. Todo SQL fica no padrão 2.5.
- **Memória / GC do C#** — o agente lê com `FbDataReader` (streaming), nunca `DataSet`/`DataTable` inteiro
  em memória. `using` em tudo (conexão, comando, reader). Snapshot serializado direto para `Stream`.

## Estratégia de execução dos indicadores

- Cada indicador é um **arquivo `.sql`** + metadados (`indicadores.json`): handle, título, tipo de
  gráfico, **cadência própria** e parâmetros.
- Aprendizado da validação: agregados mensais pesados (custo×venda, categorias) **não** precisam de
  5 min de frescor → cadência 30–60 min. Indicadores "hoje" → 5–10 min.
- `CODIGOEMPRESA` é **parâmetro**, não literal. Filtros de data **sargáveis**
  (`campo >= :ini AND campo < :fim`), nunca `cast(campo as date) = current_date`.

## Modelo de dados do backend (inicial)

- `Cliente` (id, nome, chave_api, ativo)
- `Loja` (id, cliente_id, codigo_empresa, nome)
- `UsuarioApp` (id, cliente_id, login, email, senha_hash, departamento) — hash **bcrypt/argon2** (não SHA-1)
- `Snapshot` (id, loja_id, indicador_handle, payload_json, gerado_em, recebido_em)

## Segurança

- Agente → backend: header `X-SigeDash-Key` (chave por cliente), HTTPS obrigatório.
- PWA → backend: JWT curto após login do usuário do app.
- Senhas do app **reidratadas para bcrypt** na primeira migração (não replicar SHA-1 do PlugBot).

## Roadmap

- **Fase 1 (agora):** paridade — agente + ingest + auth + PWA com os dashboards atuais (SQLs reescritos).
- **Fase 2:** novos relatórios de decisão (margem, ruptura, curva ABC, comparativos) + pré-venda mobile.
