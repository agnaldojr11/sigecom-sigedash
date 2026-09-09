# SigeDash BR — Dashboard Mobile Próprio (SistemasBr)

Produto **próprio** da SistemasBr que substitui o antigo SigeDash (Tecnospeed/PlugMobile) por uma
solução construída por nós: elimina o custo mensal recorrente de terceiros e abre uma nova linha de
receita (licenciamento por dispositivo). Entrega ao dono da loja, no celular, os indicadores de
vendas, estoque e financeiro do ERP **SIGECOM** em tempo quase real — com assistente de IA,
atualização automática e segurança de nível empresarial.

> **Status:** em produção em clientes reais, licenciado por dispositivo, com auditoria de segurança
> e LGPD aplicada. Frota monitorada pela **SigeDash Central**.

## Arquitetura em uma frase

Cada cliente roda a stack completa **no próprio servidor** (nada de dado de venda sai da loja); o
acesso remoto é via **Cloudflare Tunnel** (sem abrir portas); e a SistemasBr acompanha apenas a
**saúde operacional** da frota por telemetria sem dados pessoais.

```
Firebird 2.5 (SIGECOM)  →  Agente .NET 4.8 (read-only)  →  Backend .NET 8 + PostgreSQL  →  PWA (celular)
        [servidor do cliente]                                    [servidor do cliente]        via Cloudflare Tunnel

                                        Backend  ──(telemetria só status/versão)──►  SigeDash Central (Railway)
```

Detalhes completos em [`docs/ARQUITETURA.md`](docs/ARQUITETURA.md). Postura de segurança em
[`docs/SEGURANCA.md`](docs/SEGURANCA.md).

## Componentes

| Pasta | Conteúdo |
|---|---|
| `agente/` | Windows Service .NET Framework 4.8 (x64). Lê o Firebird **somente leitura**, executa indicadores agendados e envia snapshots JSON gzip ao backend. |
| `backend/` | API ASP.NET Core (.NET 8) + PostgreSQL. Recebe snapshots, autentica usuários do app (BCrypt + JWT, sessão única), aplica permissões/licenciamento, entrega dashboards, integra IA e envia telemetria à Central. |
| `pwa/` | App mobile (Vanilla JS + Chart.js). Login por cliente, dashboards, instalável e offline do último snapshot. Banner de auto-atualização para o admin. |
| `central/` | **SigeDash Central** (.NET 8 + PostgreSQL, hospedada na Railway). Recebe telemetria (phone-home) e serve o painel de monitoramento da frota. |
| `installer/` | **Instalador gráfico** (wizard WPF .NET 8) com a identidade do SigeDash — instala a stack completa no cliente. |
| `deploy/` | Scripts PowerShell de instalação, atualização e operação no servidor do cliente. |
| `SQLs-PlugBot/` | Config/SQLs do PlugBot antigo — **referência de escopo**. Não é código a portar. |
| `Bancos/` | Bancos .FDB de clientes para teste com dados reais. |
| `docs/` | Documentação de arquitetura e segurança. |

## Recursos principais

- **~25 indicadores** de vendas, estoque, financeiro e saldos (cadência por indicador).
- **Assistente de IA** — o dono pergunta em português e recebe resposta com base nos números da loja
  (endpoint OpenAI-compatible, provedor trocável).
- **App instalável (PWA)** — abre como aplicativo no celular, funciona offline com o último dado,
  sem depender de Play/App Store.
- **Atualização automática** — o admin vê "nova versão disponível" e atualiza com um clique;
  a correção chega a toda a frota remotamente.
- **Licenciamento por dispositivo** — limite por CNPJ definido pela SistemasBr.
- **SigeDash Central** — painel único da frota: quem está online, em que versão e se os indicadores
  estão sincronizando.
- **Segurança em camadas** — BCrypt, JWT com sessão única, bloqueio por tentativas, CSP/HSTS,
  execuções assinadas (EV) e auto-update com verificação de assinatura. Auditoria de segurança + LGPD
  aplicada. Ver [`docs/SEGURANCA.md`](docs/SEGURANCA.md).

## Fluxo resumido

1. O **Agente** executa queries no Firebird (leitura) na cadência de cada indicador.
2. Serializa em JSON, comprime com gzip e envia `POST /ingest/{empresa}/{handle}` (chave de API).
3. O **Backend** persiste o snapshot no PostgreSQL local e mantém só o mais recente por indicador.
4. O **PWA** faz login (JWT, sessão única) e busca os snapshots via `GET /dash/{empresa}`.
5. O dono acessa de qualquer celular via **Cloudflare Tunnel** (HTTPS, sem porta aberta).
6. O **Backend** envia periodicamente à **Central** apenas métricas de saúde (sem PII).

## Roadmap (Fase 2)

Novos indicadores de decisão (margem, curva ABC, comparativos), pré-venda mobile integrada ao
SIGECOM, logs/ações remotas pelo painel da frota e instalador mais leve.
