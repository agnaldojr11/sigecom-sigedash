# Changelog — SigeDash

Este arquivo registra o que entra em cada versão liberada para os clientes.
Cada mudança é anotada em **"Não liberado"** assim que fica pronta. No fim da sprint, essa seção vira a versão da sprint.
O processo está descrito em [`docs/PROCESSO-RELEASE.md`](docs/PROCESSO-RELEASE.md).

## [Não liberado] — Sprint 1

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
