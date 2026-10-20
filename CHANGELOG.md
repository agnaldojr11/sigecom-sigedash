# Changelog — SigeDash

Este arquivo registra o que entra em cada versão liberada para os clientes.
Cada mudança é anotada em **"Não liberado"** assim que fica pronta. No fim da sprint, essa seção vira a versão da sprint.
O processo está descrito em [`docs/PROCESSO-RELEASE.md`](docs/PROCESSO-RELEASE.md).

## [Não liberado] — Sprint 1 (versão 1.1.0)

Instalador disponível antes, como **pré-release v1.0.54**, só para clientes novos. A frota não recebe.

### Novo
- **Pré-verificação do servidor (PASSO 0).** Antes de alterar qualquer coisa, o instalador confere tudo o que já derrubou instalações em campo e, se houver bloqueio, **não começa** e diz o que resolver. Também pode ser rodada sozinha antes de ir ao cliente: `verificar-ambiente.ps1`. O que ela confere:
  - administrador, Windows 64 bits e versão, PowerShell, **.NET 4.8**, disco e reinício pendente;
  - pacote completo e não corrompido;
  - Firebird rodando em `localhost:3050`, `.FDB` local e leitura com SYSDBA;
  - portas 5000/5432 livres (ou do próprio SigeDash/PostgreSQL);
  - internet/TLS/proxy para Cloudflare, EnterpriseDB, GitHub e Central;
  - **firewall do túnel (TCP 7844)**;
  - token do Cloudflare do pacote válido;
  - relógio do servidor.
  - Correções seguras automáticas: desbloqueia os arquivos baixados, inicia o Firebird parado e liga o TLS 1.2 (pede reinício).
- **Relatório de instalação na Central (aba Instalações).** Toda instalação (sucesso, avisos, falha ou bloqueada) e todo `diagnostico.ps1` mandam à Central a etapa onde parou, o motivo, a pré-verificação e o log com senhas, chaves e tokens mascarados. O suporte vê sem acessar o servidor. Os relatórios são guardados por 180 dias.

### Corrigido
- **Segunda tentativa falhava com "outro erro".** Restos de um PostgreSQL que falhou no meio (binários sem banco) eram tratados como "PostgreSQL já instalado". Agora são limpos automaticamente.
- **Download do PostgreSQL (~370 MB):** 3 tentativas, BITS (retoma quedas), proxy com autenticação do Windows e cache em `C:\SigeDash\cache`. Também é possível instalar sem internet, colocando o `.exe` na pasta do instalador. O instalador do PostgreSQL agora tem limite de 30 min (antes podia travar para sempre).
- **cloudflared com versão fixa (2026.10.0) e embutido no pacote.** Antes, cada instalação baixava a "latest" do GitHub, uma versão diferente por cliente.
- **Detecção do nome/CNPJ** acha o `isql` do Firebird em qualquer versão ou pasta (antes, só 2.5/3.0 nos caminhos padrão).
- `configurar-cliente.ps1` sem `exit 0` (risco de falso "falhou com código N").
- `REQUISITOS-SERVIDOR.txt` dizia para liberar só a TCP 443. O túnel usa a **TCP 7844**.

---

## [1.0.53] — 2026‑10‑20 — Hotfix P0 (aprovado fora do calendário)

### Corrigido
- **Dados parando de sincronizar após "Atualizar agora".** O agente ficava parado quando a atualização era interrompida no meio. Nada religava o agente: ele não tinha reinício automático e o watchdog não cuidava dele.
  - O watchdog agora também garante o serviço `SigeDashAgente`.
  - O agente ganha reinício automático em caso de falha (`sc failure`), tanto na instalação quanto nos clientes já instalados (via `atualizar.ps1`).

---

## Histórico (antes do processo por sprint)

| Versão | Data | Principais mudanças |
|---|---|---|
| 1.0.52 | 2026‑10‑20 | Revisão geral do instalador: reinstalação sem travar (acesso temporário ao PostgreSQL), auto‑update no Server 2012 (sem `Expand-Archive`), serviços sempre religados na atualização, trava de manutenção do watchdog, fim dos falsos "falhou com código N". |
| 1.0.51 | 2026‑10‑20 | Detecção de empresa/CNPJ não quebra mais com perfil de usuário com acento. |
| 1.0.50 | 2026‑10‑19 | Watchdog (início do Windows + a cada 5 min) contra o 502 Bad Gateway. |
| 1.0.49 | 2026‑10‑16 | TLS 1.2 no instalador + `habilitar-tls12.ps1` (Windows Server 2012). |
| 1.0.48 | 2026‑10‑14 | Túnel força HTTP/2 (TCP 443): fim do "Degraded"/Error 1033 por QUIC bloqueado. |
| 1.0.47 | 2026‑10‑13 | Reset de senha interativo + atalho `Resetar-Senha.cmd`. |
| 1.0.46 | 2026‑10‑09 | Corrige erro 400 ao registrar cliente com acento no nome (corpo JSON em UTF‑8). |
| 1.0.45 | 2026‑10‑02 | Central: gestão de equipe e exclusão de cliente; verificação pós‑instalação; reinstalação idempotente; diagnóstico e desinstalador; correções de segurança. |
