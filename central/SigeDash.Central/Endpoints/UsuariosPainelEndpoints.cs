using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Modelos;
using SigeDash.Central.Seguranca;

namespace SigeDash.Central.Endpoints;

public record NovoUsuarioDto(string Login, string Senha, string? Papel);
public record TrocarSenhaDto(string Senha);
public record AtivoDto(bool Ativo);

/// <summary>Gestão da equipe que usa a Central (usuários do painel). Só admin gerencia.</summary>
public static class UsuariosPainelEndpoints
{
    private const int SenhaMin = 8;

    public static void MapUsuariosPainel(this IEndpointRouteBuilder app)
    {
        // Quem sou eu (login + papel) — o front usa para mostrar/esconder o menu Equipe.
        app.MapGet("/painel/eu", async (ClaimsPrincipal user, CentralDbContext db) =>
        {
            var u = await Atual(user, db);
            if (u is null) return Results.Unauthorized();
            return Results.Ok(new { u.Login, u.Papel, admin = PapelPainel.EhAdmin(u.Papel) });
        }).RequireAuthorization();

        // Lista a equipe (só admin).
        app.MapGet("/painel/usuarios", async (ClaimsPrincipal user, CentralDbContext db) =>
        {
            var (eu, erro) = await ExigeAdmin(user, db);
            if (erro is not null) return erro;

            var lista = await db.UsuariosPainel
                .OrderByDescending(x => x.Papel == PapelPainel.Admin)
                .ThenBy(x => x.Login)
                .Select(x => new
                {
                    x.Id, x.Login, x.Papel, x.Ativo, x.UltimoLoginEm, x.CriadoEm, x.CriadoPor,
                    bloqueado = x.BloqueadoAte != null && x.BloqueadoAte > DateTime.UtcNow,
                    ehEu = x.Login == eu!.Login
                })
                .ToListAsync();
            return Results.Ok(lista);
        }).RequireAuthorization();

        // Cria um acesso para um membro da equipe (só admin).
        app.MapPost("/painel/usuarios", async (NovoUsuarioDto dto, ClaimsPrincipal user, CentralDbContext db) =>
        {
            var (eu, erro) = await ExigeAdmin(user, db);
            if (erro is not null) return erro;

            var login = (dto.Login ?? "").Trim();
            if (login.Length < 3)
                return Results.BadRequest(new { erro = "Login inválido (mín. 3 caracteres)." });
            if ((dto.Senha ?? "").Length < SenhaMin)
                return Results.BadRequest(new { erro = $"Senha muito curta (mín. {SenhaMin} caracteres)." });

            var papel = (dto.Papel ?? PapelPainel.Operador).Trim().ToLowerInvariant();
            if (!PapelPainel.Todos.Contains(papel))
                return Results.BadRequest(new { erro = "Papel inválido. Use: " + string.Join(", ", PapelPainel.Todos) });

            var jaExiste = await db.UsuariosPainel.AnyAsync(x => x.Login.ToLower() == login.ToLower());
            if (jaExiste)
                return Results.Conflict(new { erro = "Já existe um usuário com esse login." });

            var novo = new UsuarioPainel
            {
                Login = login,
                SenhaHash = Auth.HashSenha(dto.Senha!),
                Papel = papel,
                Ativo = true,
                CriadoPor = eu!.Login
            };
            db.UsuariosPainel.Add(novo);
            db.LogsAuditoria.Add(new LogAuditoria
            {
                Usuario = eu.Login, Acao = "usuario_painel",
                Detalhe = $"criou o usuário '{login}' ({papel})"
            });
            await db.SaveChangesAsync();

            return Results.Ok(new { novo.Id, novo.Login, novo.Papel, novo.Ativo, novo.CriadoEm, novo.CriadoPor });
        }).RequireAuthorization();

        // Reseta a senha de um usuário (só admin).
        app.MapPost("/painel/usuarios/{id:int}/senha", async (
            int id, TrocarSenhaDto dto, ClaimsPrincipal user, CentralDbContext db) =>
        {
            var (eu, erro) = await ExigeAdmin(user, db);
            if (erro is not null) return erro;
            if ((dto.Senha ?? "").Length < SenhaMin)
                return Results.BadRequest(new { erro = $"Senha muito curta (mín. {SenhaMin} caracteres)." });

            var alvo = await db.UsuariosPainel.FirstOrDefaultAsync(x => x.Id == id);
            if (alvo is null) return Results.NotFound();

            alvo.SenhaHash = Auth.HashSenha(dto.Senha!);
            alvo.TentativasFalhas = 0;
            alvo.BloqueadoAte = null;   // reset de senha também destrava o lockout
            db.LogsAuditoria.Add(new LogAuditoria
            {
                Usuario = eu!.Login, Acao = "usuario_painel",
                Detalhe = $"redefiniu a senha de '{alvo.Login}'"
            });
            await db.SaveChangesAsync();
            return Results.Ok(new { ok = true });
        }).RequireAuthorization();

        // Ativa/desativa um usuário (só admin). Não pode desativar a si mesmo nem o último admin ativo.
        app.MapPost("/painel/usuarios/{id:int}/ativo", async (
            int id, AtivoDto dto, ClaimsPrincipal user, CentralDbContext db) =>
        {
            var (eu, erro) = await ExigeAdmin(user, db);
            if (erro is not null) return erro;

            var alvo = await db.UsuariosPainel.FirstOrDefaultAsync(x => x.Id == id);
            if (alvo is null) return Results.NotFound();
            if (alvo.Id == eu!.Id && !dto.Ativo)
                return Results.BadRequest(new { erro = "Você não pode desativar o próprio acesso." });

            if (!dto.Ativo && PapelPainel.EhAdmin(alvo.Papel))
            {
                var outrosAdmins = await db.UsuariosPainel
                    .CountAsync(x => x.Id != alvo.Id && x.Papel == PapelPainel.Admin && x.Ativo);
                if (outrosAdmins == 0)
                    return Results.BadRequest(new { erro = "Não é possível desativar o único administrador ativo." });
            }

            alvo.Ativo = dto.Ativo;
            db.LogsAuditoria.Add(new LogAuditoria
            {
                Usuario = eu.Login, Acao = "usuario_painel",
                Detalhe = (dto.Ativo ? "reativou" : "desativou") + $" o usuário '{alvo.Login}'"
            });
            await db.SaveChangesAsync();
            return Results.Ok(new { alvo.Id, alvo.Ativo });
        }).RequireAuthorization();

        // Exclui um usuário (só admin). Não pode excluir a si mesmo nem o último admin.
        app.MapDelete("/painel/usuarios/{id:int}", async (
            int id, ClaimsPrincipal user, CentralDbContext db) =>
        {
            var (eu, erro) = await ExigeAdmin(user, db);
            if (erro is not null) return erro;

            var alvo = await db.UsuariosPainel.FirstOrDefaultAsync(x => x.Id == id);
            if (alvo is null) return Results.NotFound();
            if (alvo.Id == eu!.Id)
                return Results.BadRequest(new { erro = "Você não pode excluir o próprio acesso." });

            if (PapelPainel.EhAdmin(alvo.Papel))
            {
                var outrosAdmins = await db.UsuariosPainel.CountAsync(x => x.Id != alvo.Id && x.Papel == PapelPainel.Admin);
                if (outrosAdmins == 0)
                    return Results.BadRequest(new { erro = "Não é possível excluir o único administrador." });
            }

            db.UsuariosPainel.Remove(alvo);
            db.LogsAuditoria.Add(new LogAuditoria
            {
                Usuario = eu.Login, Acao = "usuario_painel",
                Detalhe = $"excluiu o usuário '{alvo.Login}'"
            });
            await db.SaveChangesAsync();
            return Results.Ok(new { ok = true });
        }).RequireAuthorization();
    }

    private static async Task<UsuarioPainel?> Atual(ClaimsPrincipal user, CentralDbContext db)
    {
        var login = user.FindFirstValue("login") ?? user.Identity?.Name;
        if (string.IsNullOrEmpty(login)) return null;
        return await db.UsuariosPainel.FirstOrDefaultAsync(u => u.Login == login);
    }

    /// <summary>Retorna o usuário atual se for admin ativo; senão devolve o IResult de erro (401/403).</summary>
    private static async Task<(UsuarioPainel? eu, IResult? erro)> ExigeAdmin(ClaimsPrincipal user, CentralDbContext db)
    {
        var eu = await Atual(user, db);
        if (eu is null || !eu.Ativo) return (null, Results.Unauthorized());
        if (!PapelPainel.EhAdmin(eu.Papel))
            return (null, Results.Json(new { erro = "Apenas administradores podem gerenciar a equipe." }, statusCode: 403));
        return (eu, null);
    }
}
