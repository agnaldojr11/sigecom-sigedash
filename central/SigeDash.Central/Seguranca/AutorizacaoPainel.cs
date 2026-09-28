using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using SigeDash.Central.Data;
using SigeDash.Central.Modelos;

namespace SigeDash.Central.Seguranca;

/// <summary>Helpers de autorização do painel (usuário atual + exigência de admin).</summary>
public static class AutorizacaoPainel
{
    /// <summary>Carrega o usuário do painel a partir do claim de login do JWT.</summary>
    public static async Task<UsuarioPainel?> AtualAsync(ClaimsPrincipal user, CentralDbContext db)
    {
        var login = user.FindFirstValue("login") ?? user.Identity?.Name;
        if (string.IsNullOrEmpty(login)) return null;
        return await db.UsuariosPainel.FirstOrDefaultAsync(u => u.Login == login);
    }

    /// <summary>Retorna o usuário atual se for admin ativo; senão devolve o IResult de erro (401/403).</summary>
    public static async Task<(UsuarioPainel? eu, IResult? erro)> ExigeAdminAsync(ClaimsPrincipal user, CentralDbContext db)
    {
        var eu = await AtualAsync(user, db);
        if (eu is null || !eu.Ativo) return (null, Results.Unauthorized());
        if (!PapelPainel.EhAdmin(eu.Papel))
            return (null, Results.Json(new { erro = "Apenas administradores podem executar esta ação." }, statusCode: 403));
        return (eu, null);
    }
}
