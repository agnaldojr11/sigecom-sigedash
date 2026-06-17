# SigeDash BR — Dashboard Mobile Próprio (SistemasBr)

Substitui o SigeDash (Tecnospeed/PlugMobile) por solução própria, eliminando o custo mensal
e abrindo caminho para pré-venda mobile integrada ao SIGECOM.

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `agente/` | Windows Service .NET Framework 4.8 (x64). Lê o Firebird read-only, executa indicadores agendados e envia JSON gzip ao backend. |
| `backend/` | API ASP.NET Core (.NET 8) + PostgreSQL. Recebe snapshots, autentica usuários do app, entrega dashboards. |
| `pwa/` | App mobile (Vanilla JS + Chart.js). Login por cliente, dashboards, instalável e offline do último snapshot. |
| `SQLs-PlugBot/` | Config/SQLs do PlugBot atual — **referência de escopo** (paridade Fase 1). Não é código a portar. |
| `Bancos/` | Bancos .FDB de clientes para teste com dados reais. |
| `docs/ARQUITETURA.md` | Decisões, fluxo e restrições (FB 2.5, charset, memória). |
| `VALIDACAO-SQLs-PlugBot.md` | Resultado da validação dos SQLs de referência no banco real. |

## Fase 1 (atual) — paridade

Reproduzir os indicadores do SigeDash atual, com **SQLs reescritos e otimizados por nós**:
empresa parametrizada, filtros de data sargáveis, cadência ajustada por indicador.

Indicadores iniciais (em `agente/.../Indicadores/indicadores.json`):
vendas (total hoje, top 5 produtos, custo×venda), estoque (abaixo do mínimo).

## Fase 2 — novidades

Novos relatórios de decisão (margem, ruptura, curva ABC, comparativos) e pré-venda mobile
(canal agente↔backend vira bidirecional).

## Fluxo

`Firebird 2.5 (cliente)` → `Agente .NET 4.8 (read-only)` → `HTTPS/JSON` → `Backend + PostgreSQL` → `PWA`

Detalhes em `docs/ARQUITETURA.md`.
