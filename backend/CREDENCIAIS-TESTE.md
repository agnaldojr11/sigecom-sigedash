# Credenciais de teste — SigeDash (DEV)

> Geradas pelo seed automático (`SeedData.cs`), só em ambiente Development.
> Senhas convertidas das originais do SIGECOM (SHA-1) para **bcrypt** no backend.

## Login do app (PWA)  →  POST /auth/login
- **Empresa (cliente):** `5 Estrelas`
- **Usuários:**

| Usuário | Senha | Departamento |
|---|---|---|
| `GILMAR`  | `123` | Vendedores |
| `RONAN`   | `123` | Administradores |
| `ESTOQUE` | `123` | Estoque |
| `AUTO`    | `123` | Administradores |
| `JESSICA` | `7514` | Administradores |
| `ADMIN`   | `sigedash@123` | Administradores (conveniência) |

Exemplo:
```json
POST /auth/login
{ "cliente": "5 Estrelas", "login": "GILMAR", "senha": "123" }
```

## Agente → backend  (header)
- `X-SigeDash-Key: TESTE-5ESTRELAS-0001`
- Empresa (CODIGOEMPRESA): `1`

## Agente → Firebird (banco de teste)
- Usuário: `SYSDBA`  Senha: `masterkey`
- DB: `5ESTRELAS.FDB`  (CODIGOEMPRESA = 1)
