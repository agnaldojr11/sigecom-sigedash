# SigeDash Central — deploy no Railway (Fase 1)

Serviço central de telemetria + painel da frota. Stack: **.NET 8 + PostgreSQL** (Dockerfile).
Pasta do projeto: `central/SigeDash.Central`.

---

## 1. Criar o projeto no Railway

1. Railway → **New Project** → **Deploy from GitHub repo** → selecione `agnaldojr11/sigecom-sigedash`.
2. Após criar o serviço, abra **Settings → Source**:
   - **Root Directory:** `central/SigeDash.Central`
   - **Builder:** Dockerfile (o Railway detecta o `Dockerfile` automaticamente).
3. Ainda em Settings → **Networking → Generate Domain** (gera `xxxx.up.railway.app`).
   Depois, opcional: **Custom Domain** `central.sigedash.com.br` → o Railway mostra um CNAME → crie no DNS do Cloudflare (pode deixar *DNS only*).

## 2. Adicionar o PostgreSQL

1. No mesmo projeto: **New → Database → PostgreSQL** (1 clique).
2. No **serviço do Central** → aba **Variables** → adicione uma referência ao banco:
   - `DATABASE_URL` = `${{Postgres.DATABASE_URL}}`

## 3. Variáveis de ambiente (no serviço do Central)

| Variável | Valor | Para quê |
|---|---|---|
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | conexão com o Postgres |
| `Jwt__SecretKey` | string aleatória **32+** chars | assina o login do painel |
| `Painel__AdminLogin` | ex.: `admin` | usuário do painel |
| `Painel__AdminSenha` | senha forte | senha do painel (semeada no 1º boot) |
| `Central__AdminKey` | chave forte | autoriza o registro de clientes |

> `PORT` é injetado pelo Railway automaticamente — não precisa definir.
> Use `__` (dois underscores) para as chaves aninhadas (padrão .NET no ambiente).

Gerar segredos rápidos (PowerShell):
```powershell
[Convert]::ToBase64String((1..48 | % {[byte](Get-Random -Max 256)}))   # Jwt__SecretKey
[Convert]::ToBase64String((1..32 | % {[byte](Get-Random -Max 256)}))   # Central__AdminKey
```

## 4. Deploy

O Railway builda o Dockerfile e sobe. No 1º boot o Central:
- **migra o banco** (cria as tabelas) e
- **semeia o usuário do painel** a partir de `Painel__AdminLogin`/`Painel__AdminSenha`.

Confira em **Deploy Logs**: `Usuário do painel 'admin' criado.` e o serviço escutando na porta.
Teste: abra `https://SEU-DOMINIO/health` → deve responder `{ "ok": true }`.

## 5. Entrar no painel

Abra `https://SEU-DOMINIO/` → login com `Painel__AdminLogin` / `Painel__AdminSenha`.
A frota aparece vazia até registrar os clientes.

## 6. Registrar os clientes na frota

Para cada cliente, chame `POST /admin/clientes` com o header `X-Admin-Key`. Retorna a **ChaveTelemetria** (guarde — vai no backend do cliente):

```powershell
$central = "https://central.sigedash.com.br"
$adminKey = "<Central__AdminKey>"
$body = @{ nome = "Loja 5 Estrelas"; cnpj = "00.000.000/0001-00"; limiteDispositivos = 3 } | ConvertTo-Json
$r = Invoke-RestMethod -Uri "$central/admin/clientes" -Method POST `
     -Headers @{ "X-Admin-Key" = $adminKey; "Content-Type" = "application/json" } -Body $body
"ChaveTelemetria: $($r.chaveTelemetria)"
```

Listar/conferir: `GET /admin/clientes` (mesmo header). Rotacionar chave: `POST /admin/clientes/{id}/rotacionar-chave`.

## 7. Ligar a telemetria em cada cliente

No servidor de cada cliente, no `C:\SigeDash\Backend\appsettings.Production.json`, adicione o bloco `Central` com a chave daquele cliente e reinicie o backend:

```powershell
$cfg = "C:\SigeDash\Backend\appsettings.Production.json"
$j = Get-Content $cfg -Raw | ConvertFrom-Json
$central = [PSCustomObject]@{ Url = "https://central.sigedash.com.br"; ChaveTelemetria = "SGT-...cole..."; IntervaloMin = 3 }
$j | Add-Member -NotePropertyName Central -NotePropertyValue $central -Force
$j | ConvertTo-Json -Depth 10 | Set-Content $cfg -Encoding UTF8
Restart-Service SigeDashBackend -Force
```

> ⚠️ A telemetria só existe no backend a partir da **versão que inclui o `TelemetriaHostedService`** (v1.0.39+). Fluxo: publicar essa versão → clientes atualizam (banner/auto-update) → aí sim configurar o bloco `Central` em cada um. Em ~20s começam os heartbeats e o painel mostra os clientes **online**.

## Endpoints (resumo)

| Método | Rota | Auth | Função |
|---|---|---|---|
| GET  | `/health` | — | healthcheck |
| POST | `/telemetria/heartbeat` | `X-Telemetria-Key` | cliente envia estado |
| POST | `/painel/login` | — | login do painel → JWT |
| GET  | `/painel/frota` | JWT | resumo + lista de clientes |
| GET  | `/painel/clientes/{id}` | JWT | detalhe do cliente |
| POST | `/admin/clientes` | `X-Admin-Key` | registra cliente → ChaveTelemetria |
| GET  | `/admin/clientes` | `X-Admin-Key` | lista clientes/chaves |

## Segurança

- Telemetria só de **saída** do cliente; nenhuma porta nova exposta.
- Só métrica operacional — **sem** dados de venda/PII/senha.
- Chave por cliente (revogável). Painel protegido por login (BCrypt + JWT).
