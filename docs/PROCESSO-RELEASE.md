# Processo de desenvolvimento e liberação de versões — SigeDash

## Por que este processo existe

Toda versão publicada como **release normal ("latest")** no GitHub vira atualização para **toda a frota**: o admin do cliente vê o botão **"Atualizar agora"** e, além disso, o auto‑update roda **toda segunda às 03:00**.

Em outubro/2026 publicamos 8 versões (v1.0.45 a v1.0.52) em cerca de 3 semanas. Os clientes passaram a atualizar o tempo todo, e uma dessas atualizações deixou o **agente parado** em alguns clientes: o app abria, mas os dados pararam de sincronizar.

**A partir de agora, a frota só recebe versão no fim de cada sprint.** Correções urgentes de verdade (P0) são a única exceção.

---

## Fluxo de trabalho (Kanban)

| Coluna | O que significa | Limite |
|---|---|---|
| **Backlog** | Tudo que foi pedido ou encontrado, priorizado | — |
| **Sprint – A fazer** | O que foi comprometido para a sprint atual | — |
| **Em andamento** | Alguém está trabalhando agora | máx. 3 |
| **Revisão / QA** | Pronto no código, em teste | máx. 3 |
| **Pronto para release** | Testado, aguardando o fim da sprint | — |
| **Liberado** | Já está na release da sprint (cliente recebeu) | — |

**Etiquetas de cada cartão**
- **Tipo:** `bug` · `melhoria` · `feature` · `hotfix`
- **Prioridade:**
  - **P0** — sistema fora do ar, dados parados em produção ou falha de segurança. É o único tipo que justifica hotfix.
  - **P1** — afeta vários clientes, mas tem contorno.
  - **P2** — afeta pouco ou é incômodo.
  - **P3** — desejável.
- **Componente:** `backend` · `agente` · `pwa` · `instalador` · `central`

**Definição de Pronto (para o cartão ir a "Pronto para release")**
1. Código commitado e o build passa.
2. Scripts `.ps1` alterados passam na validação de sintaxe.
3. Testado no ambiente de teste (instalação ou atualização, conforme o caso).
4. Entrada escrita no `CHANGELOG.md`, na seção **"Não liberado"**.

---

## Sprint

- **Duração:** 2 semanas.
- **Início:** planejamento. A equipe puxa do Backlog o que cabe na sprint.
- **Congelamento:** nos 2 últimos dias úteis entram só correções, nada de funcionalidade nova.
- **Último dia útil:** checklist de release (abaixo) e publicação da versão da sprint.
- **Versão:** a sprint aumenta o número do meio (1.1.0, 1.2.0…). Um hotfix aumenta o último número (1.1.1).

---

## Canais de versão — como a frota é protegida

O `atualizar.ps1` e o botão "Atualizar agora" consultam **apenas a release normal mais recente (latest)**. **Pré‑releases são ignoradas.**

| Situação | Como publicar | Quem recebe |
|---|---|---|
| **Durante a sprint** (qualquer build, correção ou teste) | `gh release create vX.Y.Z --prerelease` | **Ninguém automaticamente.** O suporte pode baixar o instalador pelo menu **Versões** da Central para um **cliente novo** que precise daquela correção. |
| **Fim da sprint** (versão aprovada no checklist) | release normal (latest) | A frota inteira, **no máximo uma vez por sprint** (botão + segunda 03:00). |
| **Hotfix P0** (exceção) | release normal, fora do calendário, **com aprovação do responsável** | A frota inteira. |

> Regra de ouro: **nada vira "latest" sem passar pelo checklist abaixo.**

---

## Checklist de release (antes de marcar como latest)

1. **Instalação limpa** em VM Windows Server 2019/2022: o PASSO 6 passa (empresa cadastrada + acesso externo OK).
2. **Windows Server 2012 R2** (se ainda houver clientes nele): instalação após rodar `habilitar-tls12.ps1`.
3. **Atualização a partir da versão que a frota está usando hoje** (o teste mais importante). Pelo botão "Atualizar agora", conferir:
   - os serviços `SigeDashBackend`, `SigeDashAgente` e `cloudflared` estão **Running**;
   - os **dados continuam sincronizando**: "Dados sincronizados em…" recente no app, e nenhum indicador "atrasado" na Central.
4. **Reinstalação** (`desinstalar-tudo.ps1` + instalar de novo): mantém a mesma URL.
5. **Assinatura:** `SigeDash.Api.exe`, `SigeDash.Agente.exe` e o instalador com status **Valid** e signatário **SISTEMASBR**.
6. **Notas da release** montadas a partir do `CHANGELOG.md`.
7. **Depois de publicar:** acompanhar a Central por 24h (versão de cada cliente, online/offline, indicadores com erro ou atrasados).

---

## Se os dados pararem de sincronizar num cliente

1. No servidor do cliente, como Administrador:
   ```powershell
   Get-Service SigeDashAgente
   Start-Service SigeDashAgente
   ```
2. Se o serviço não ficar em Running:
   ```powershell
   powershell -ExecutionPolicy Bypass -File "C:\SigeDash\Backend\diagnostico.ps1"
   ```
3. Envie ao suporte as últimas linhas de `C:\SigeDash\Backend\atualizar.log` e o relatório do diagnóstico.

> A partir da versão com o watchdog cobrindo o agente, ele é religado sozinho em até 5 minutos.
