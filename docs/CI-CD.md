# SigeDash — Guia de CI/CD

**Equipe:** TI SistemasBr  
**Pré-requisito:** repositório no GitHub com os arquivos `.github/workflows/`

---

## Fluxo Resumido

```
git tag v1.2.3
git push --tags
      │
      ├── ci.yml ──────── build e valida (backend + agente + docker)
      │
      ├── deploy.yml ───── build imagem Docker
      │                    → push ghcr.io/sistemasbr/sigecom-sigedash:v1.2.3
      │                    → SSH no VPS → docker compose pull → restart
      │
      └── build-agente.yml ── compila agente .NET 4.8
                               → gera SigeDashAgente-Setup-v1.2.3.exe
                               → cria GitHub Release com o .exe anexado
```

O técnico de suporte baixa o `.exe` direto da aba **Releases** do repositório e leva ao cliente.

---

## 1 — Criar repositório no GitHub

1. Acesse [github.com](https://github.com) e crie um repositório privado:  
   **`sistemasbr/sigecom-sigedash`** (ou o nome que preferir)
2. Faça o primeiro push:
   ```bash
   cd C:\Users\Dell\Desktop\ClaudeSigecom\sigedash-br
   git init
   git remote add origin https://github.com/sistemasbr/sigecom-sigedash.git
   git add .
   git commit -m "feat: setup inicial SigeDash"
   git push -u origin main
   ```

---

## 2 — Configurar Secrets do GitHub

Acesse: **Repositório → Settings → Secrets and variables → Actions → New repository secret**

### Secrets obrigatórios para deploy no VPS

| Secret | Valor | Como obter |
|---|---|---|
| `VPS_HOST` | IP ou hostname do VPS | Ex: `123.45.67.89` |
| `VPS_USER` | Usuário SSH | Ex: `deploy` ou `root` |
| `VPS_SSH_KEY` | Chave privada SSH | Conteúdo do arquivo `~/.ssh/id_rsa` |
| `VPS_DEPLOY_PATH` | Pasta do projeto no VPS | Ex: `/opt/sigedash` |
| `GHCR_TOKEN` | GitHub PAT com `read:packages` | Veja passo 2.1 abaixo |

### 2.1 — Gerar o GHCR_TOKEN (token para o VPS fazer pull da imagem)

1. GitHub → **Settings (seu perfil)** → Developer settings → Personal access tokens → Tokens (classic)
2. **Generate new token (classic)**
3. Marque: `read:packages`
4. Copie o token gerado
5. Adicione como secret `GHCR_TOKEN` no repositório

> O `GITHUB_TOKEN` automático do Actions já tem `write:packages` para o push.  
> O `GHCR_TOKEN` é necessário apenas no VPS (passo de deploy via SSH) para fazer `docker pull`.

---

## 3 — Preparar o VPS

### 3.1 — Usuário de deploy (recomendado)

```bash
# No VPS como root
useradd -m -s /bin/bash deploy
usermod -aG docker deploy

# Cria par de chaves SSH para o GitHub Actions
ssh-keygen -t ed25519 -f /home/deploy/.ssh/github_actions -N ""
cat /home/deploy/.ssh/github_actions.pub >> /home/deploy/.ssh/authorized_keys
chmod 600 /home/deploy/.ssh/authorized_keys

# O conteúdo abaixo vai no secret VPS_SSH_KEY:
cat /home/deploy/.ssh/github_actions
```

### 3.2 — Estrutura de pastas no VPS

```bash
mkdir -p /opt/sigedash/nginx/certs
chown -R deploy:deploy /opt/sigedash
```

### 3.3 — Arquivo .env no VPS

```bash
cd /opt/sigedash
cp .env.example .env
nano .env   # preencha com os valores reais
```

O campo `BACKEND_IMAGE` será **atualizado automaticamente** pelo pipeline a cada deploy.

---

## 4 — Primeiro deploy manual (uma única vez)

Antes do CI/CD funcionar, suba o VPS manualmente para validar:

```bash
# No VPS
cd /opt/sigedash

# Faz build local da primeira vez (sem imagem no registry ainda)
docker compose build
docker compose up -d

# Verifica
docker compose ps
curl http://localhost:8080
```

Depois que o CI/CD estiver configurado, nunca mais será necessário fazer build manual.

---

## 5 — Lançar uma versão

```bash
# Na sua máquina de dev
git add .
git commit -m "feat: nova funcionalidade X"
git push

# Cria a tag de versão
git tag v1.2.3
git push --tags
```

Isso dispara **automaticamente**:
1. `ci.yml` — valida o build
2. `deploy.yml` — publica nova imagem + atualiza o VPS
3. `build-agente.yml` — gera o instalador `.exe` e cria o GitHub Release

O instalador fica disponível em:  
`https://github.com/sistemasbr/sigecom-sigedash/releases/tag/v1.2.3`

---

## 6 — Estratégia de branches

| Branch | Quando usar | Trigger CI/CD |
|---|---|---|
| `develop` | Desenvolvimento diário | Só CI (build, sem deploy) |
| `main` | Código estável, pronto para versão | CI |
| `v*.*.*` (tag) | Lançamento de versão | CI + Deploy + Build agente |

Fluxo recomendado:
```
develop → (merge) → main → (tag v1.x.x) → deploy automático
```

---

## 7 — Migrar para Azure ou AWS (futuro)

### Azure Container Apps

No `deploy.yml`, substitua o job `deploy-vps` pelo job `deploy-azure` (comentado no arquivo).  
Secrets adicionais: `AZURE_WEBAPP_NAME`, `AZURE_WEBAPP_PUBLISH_PROFILE`.

### AWS App Runner / ECS

1. Adicione: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`
2. Troque o registry de `ghcr.io` para `<account>.dkr.ecr.<region>.amazonaws.com`
3. Use a action `aws-actions/amazon-ecs-deploy-task-definition`

A arquitetura Docker/Compose já é compatível com ambas as plataformas — só muda o destino do push e o comando de deploy.

---

## Referência rápida

| Ação | Comando |
|---|---|
| Lançar versão | `git tag v1.2.3 && git push --tags` |
| Ver status dos pipelines | GitHub → Actions |
| Baixar instalador do agente | GitHub → Releases |
| Ver logs do deploy | GitHub → Actions → deploy.yml → último run |
| Rollback de versão | `git tag v1.2.3-rollback <commit> && git push --tags` |
