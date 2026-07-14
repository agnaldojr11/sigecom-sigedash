# Segurança do SigeDash

Guia da estrutura de segurança do projeto: auditoria assistida por IA, automação no pipeline e o
gate de release. Objetivo: nenhuma versão vai para a rua com dependência vulnerável, segredo vazado
ou regressão de segurança — especialmente porque cada cliente fica exposto via Cloudflare Tunnel.

## 1. Agente "Segurança" (auditoria sob demanda)

`.claude/agents/seguranca.md` define um subagente Engenheiro Sênior de CyberSecurity, calibrado para
a nossa stack (.NET 8, EF/PostgreSQL, agente .NET 4.8, PWA JS puro, Cloudflare Tunnel, GitHub Actions).

Como usar (no Claude Code):
- "Rode o agente **Segurança** e faça a auditoria completa antes da v1.0.x"
- Ele segue 10 etapas (inventário → dependências → SAST → DAST → pentest → infra → headers → LGPD →
  score → relatório final) e grava tudo em `security-reports/*.md`, com PoC e correção sugerida.
- **Não altera o código-fonte** — só relata. As correções são aplicadas pelo time após aprovação.

Recomendação: rodar a auditoria completa antes de cada release "grande" (mudança de auth, novo
endpoint, mudança de infra) e uma revisão rápida a cada versão.

## 2. Automação no pipeline (`.github/workflows/security.yml`)

Roda em push na `main`, PRs, **cada tag `v*.*.*`**, semanalmente (seg 06:00 UTC) e sob demanda:

| Job | O que faz | Bloqueia? |
|-----|-----------|-----------|
| **segredos** | `gitleaks` — procura chaves/senhas/tokens vazados no histórico | Sim |
| **dependencias** | `dotnet list package --vulnerable` no backend (CVEs) | Sim |
| **trivy** | `trivy fs` — vulnerabilidades + segredos + misconfig | Relatório (por ora) |

Os relatórios ficam como artifacts do run. O Trivy começa em modo relatório (`exit-code: 0`); depois
de zerarmos os achados, trocar para `1` para também bloquear.

## 3. Gate de release (opcional, recomendado)

Para impedir que uma tag de versão publique com problema, o job de release passa a depender da
segurança. Em `.github/workflows/release.yml`, no job `release`, adicionar:

```yaml
jobs:
  release:
    needs: [seguranca-gate]   # não publica se a segurança falhar
    ...
```

Como `security.yml` e `release.yml` são workflows separados, a forma simples é **replicar os jobs
`segredos` e `dependencias` dentro do `release.yml`** como um job `seguranca-gate` e usar `needs`.
(Só habilitar depois que os achados atuais estiverem corrigidos — senão nenhuma versão sai.)

## 4. Achados atuais (a corrigir antes de habilitar o gate)

Detectados por `dotnet list package --vulnerable` (2026-07-14):

| Pacote (transitivo) | Versão | Sev. | Aviso | Correção |
|---|---|---|---|---|
| Microsoft.Extensions.Caching.Memory | 8.0.0 | High | GHSA-qj66-m88j-hmgj (DoS) | fixar ≥ 8.0.1 |
| System.Text.Json | 8.0.4 | High | GHSA-8g4q-xg66-9fp4 (DoS) | fixar ≥ 8.0.5 |

Correção: fixar os pacotes patched no `SigeDash.Api.csproj` (referência direta) ou subir o stack
EF/ASP.NET para o último patch 8.0.x. O agente (.NET 4.8) está sem vulnerabilidades.

## 5. Roadmap de hardening (candidatos)

- Ligar o gate de release após corrigir os achados.
- Headers de segurança no backend (CSP, HSTS, X-Content-Type-Options, Referrer-Policy, Permissions-Policy).
- Revisar rate limiting (hoje só no `/auth/login`) e proteção de brute force por usuário, não só por IP.
- Migrar hashing de senha (hoje SHA-1, herdado do SIGECOM) para algo forte quando viável.
- CodeQL (C#/JS) — requer GitHub Advanced Security no repositório privado.
- Log de auditoria (quem/quando) — complementa a sessão única.
