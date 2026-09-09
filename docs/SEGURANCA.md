# Segurança do SigeDash

Postura de segurança do produto e como ela é mantida. O contexto que motiva esse rigor: **cada
cliente fica acessível pela internet** (via Cloudflare Tunnel), então a segurança foi tratada como
requisito de produto, em camadas (defesa em profundidade), e **validada por auditoria independente**
antes de escalar a base de clientes.

> Última auditoria completa (código + LGPD): **2026-08-20**. Achados críticos e altos corrigidos;
> telemetria confirmada **sem nenhum dado pessoal**. Ver §5.

---

## 1. Autenticação e sessão

| Item | Como está hoje |
|---|---|
| **Hash de senha** | **BCrypt** (`BCrypt.Net-Next`), fator de trabalho 12. Nunca em texto, nunca SHA-1. |
| **Usuários** | Nativos do SigeDash (`UsuarioApp`), criados pelo ADM da empresa — não mais derivados do Firebird. |
| **Token** | **JWT HS256** com expiração; claims `cliente_id`, `usuario_id`, `admin`, `sid`. Algoritmo travado na validação (sem `alg=none`). |
| **Sessão única** | O login novo grava um `sid` no token e em `UsuarioApp.SessaoToken`; qualquer requisição de um `sid` divergente cai em 401 (last-login-wins). Derruba o dispositivo anterior. |
| **Primeiro acesso** | Senha temporária gerada na instalação, com **troca obrigatória** no primeiro login. |
| **Bloqueio (lockout)** | Após tentativas erradas o login é bloqueado temporariamente (anti-brute-force por usuário, não só por IP). |
| **Rate limiting** | Políticas por IP no `/auth/login` e demais fluxos sensíveis. |
| **Armazenamento no cliente** | JWT em `sessionStorage` (limpo ao fechar a aba). |
| **2FA (TOTP)** | Estrutura preparada no modelo (`TotpSecret`/`TotpAtivado`); ativação no fluxo de login está no roadmap. |

## 2. Autorização

- **Isolamento por cliente:** toda consulta é filtrada por `cliente_id` do token — é impossível um
  usuário ver dados de outra loja.
- **Papel de admin revalidado no banco** a cada ação sensível (não se confia apenas no claim do token).
- **Permissões por usuário:** cada usuário vê somente as seções liberadas pelo ADM da empresa
  (trava tanto no backend quanto na UI).
- **Licenciamento por dispositivo:** limite por CNPJ (`Cliente.LimiteDispositivos`, 0 = ilimitado),
  definido apenas pela SistemasBr; trava a criação de usuários acima do limite.

## 3. Rede, exposição e infraestrutura

- **Nenhuma porta aberta** no servidor do cliente: o acesso externo é só via **Cloudflare Tunnel**
  (HTTPS, sem IP fixo). O backend e o PostgreSQL escutam apenas em `localhost`.
- **Gate local:** operações administrativas/sensíveis são **bloqueadas fora da rede local**
  (verificação de origem local, com normalização de path para não ser burlada por barra final — fix M-01).
- **PostgreSQL** local, autenticação **scram-sha-256**, senha forte gerada na instalação.
- **Cabeçalhos de segurança** no backend: CSP restrita, **HSTS**, `X-Content-Type-Options: nosniff`,
  `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`.
- **Firebird** lido **somente em modo leitura** — zero impacto e zero risco de escrita no ERP em produção.
- **Auto-recuperação:** serviços Windows com dependência do PostgreSQL + reinício automático em falha.

## 4. Segredos e cadeia de entrega

- **Geração de segredos** por CSPRNG (chaves de telemetria/admin não previsíveis).
- **Comparação de chaves em tempo constante** (`FixedTimeEquals`) nos endpoints com `X-Admin-Key` /
  `X-Telemetria-Key` — sem vazamento por timing.
- **ACL de disco:** `appsettings.Production.json` e pastas sensíveis com permissão só de
  Administrador/SYSTEM.
- **Nenhum segredo no repositório:** `.gitignore` cobre chaves/relatórios; varredura automática
  (gitleaks) no CI. Segredos que circularam foram **rotacionados**.
- **Assinatura de código (EV DigiCert):** executáveis assinados (sem alerta do SmartScreen).
- **Auto-update seguro (A-03):** o `atualizar.ps1` **só aplica pacote com assinatura Authenticode
  válida** da SistemasBr (assinante deve conter `SISTEMASBR`); aborta caso contrário.

## 5. Auditoria de segurança + LGPD (2026-08-20)

Auditoria completa (SAST + dependências + autenticação/JWT + autorização + infraestrutura + headers +
LGPD) do backend, da Central, do agente e do PWA, executada pelo subagente **Segurança** (§6).
Pacote de hardening implementado e publicado:

| ID | Achado | Status |
|---|---|---|
| **A-01** | JWT sem fail-fast (fallback público inseguro) na Central | Corrigido — falha na inicialização se a chave for fraca/ausente |
| **A-02** | Rate limiting ausente na Central | Corrigido — políticas login/admin/telemetria |
| **A-03** | Auto-update sem verificar assinatura | Corrigido — verificação Authenticode obrigatória |
| **M-01** | Gate local burlável por barra final | Corrigido — normalização de path |
| **M-03** | Faltavam headers de segurança na Central | Corrigido — CSP/HSTS/nosniff/frame |
| **M-04** | Telemetria sem limites de tamanho/quantidade | Corrigido — truncamento + cap de indicadores |
| **B-02** | Comparação de `X-Admin-Key` não constante | Corrigido — `FixedTimeEquals` |
| **B-05** | Retenção/expurgo de dados (LGPD) | Corrigido — expurgo automático (histórico da Central + snapshots do backend) |
| **C-01** | Segredos da Central em arquivo no repo | Corrigido — gitignore + segredos **rotacionados** |
| **M-02** | Senha padrão do Firebird (`SYSDBA/masterkey`) | **Risco aceito** — padrão do SIGECOM, imutável; mitigado por localhost-only + agente read-only + gate local + ACL |

### LGPD por construção

- **Minimização:** a Central recebe **só** versão, uso e status operacional — nenhum nome, valor de
  venda ou dado pessoal. Confirmado na auditoria.
- **Isolamento:** um servidor por cliente, sem cruzamento de dados entre lojas.
- **Em trânsito:** tudo por HTTPS (Cloudflare Tunnel).
- **Retenção:** expurgo automático do histórico (Central) e de snapshots antigos (backend) —
  mantém-se apenas o snapshot mais recente por indicador.

## 6. Agente "Segurança" (auditoria sob demanda)

`.claude/agents/seguranca.md` define um subagente Engenheiro Sênior de CyberSecurity, calibrado para
a nossa stack (.NET 8, EF/PostgreSQL, agente .NET 4.8, PWA JS puro, Cloudflare Tunnel, Central,
GitHub Actions).

- Segue etapas de inventário → dependências → SAST → DAST → pentest → infra → headers → LGPD →
  score → relatório, e grava relatórios `.md` com PoC e correção sugerida.
- **Não altera o código-fonte** — só relata; as correções são aplicadas pelo time após aprovação.
- Recomendação: auditoria completa antes de cada release "grande" (mudança de auth, novo endpoint,
  mudança de infra) e revisão rápida a cada versão.
- **Regra operacional:** nunca apontar pentest ativo para os túneis de clientes em produção.

## 7. Automação no pipeline

`.github/workflows/security.yml` (push na `main`, PRs, cada tag `v*.*.*`, semanal e sob demanda):

| Job | O que faz | Bloqueia? |
|-----|-----------|-----------|
| **segredos** | `gitleaks` — chaves/senhas/tokens vazados no histórico | Sim |
| **dependencias** | `dotnet list package --vulnerable` (CVEs) | Sim |
| **trivy** | `trivy fs` — vulnerabilidades + segredos + misconfig | Relatório |

### Gate de release (ATIVO)

`.github/workflows/release.yml` tem um job `seguranca` (gitleaks + `dotnet list --vulnerable`) e o job
`release` usa `needs: [seguranca]` — **nenhuma tag publica se houver segredo vazado ou dependência
vulnerável**. Se o gate falhar, corrija o achado e re-tague. As dependências vulneráveis apontadas na
auditoria de 2026-07 (Microsoft.Extensions.Caching.Memory, System.Text.Json) já foram atualizadas.

## 8. Roadmap de hardening

- Ativar 2FA (TOTP) no fluxo de login (estrutura já no modelo).
- Trocar o Trivy do `security.yml` para `exit-code: 1` (bloquear, não só relatar).
- CodeQL (C#/JS) — requer GitHub Advanced Security no repositório privado.
- Log de auditoria centralizado (quem/quando) pela Central.
- LGPD documental: RoPA, documentação de operador/subprocessador.
