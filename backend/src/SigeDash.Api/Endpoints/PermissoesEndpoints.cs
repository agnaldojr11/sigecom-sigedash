using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;

namespace SigeDash.Api.Endpoints;

public record SetPermissoesDto(string[] Secoes);

/// <summary>
/// Gestao de permissoes por usuario. Somente para admins (USUARIO.CODIGOTIPO == 1),
/// verificado pelo claim "admin" do JWT. Escopado ao cliente do admin logado.
/// </summary>
public static class PermissoesEndpoints
{
    public static void MapPermissoes(this IEndpointRouteBuilder app)
    {
        // Lista os usuarios do cliente com tipo e secoes liberadas (para a tela de Permissoes)
        app.MapGet("/admin/usuarios", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();
            var clienteId = int.Parse(user.FindFirstValue("cliente_id")!);

            var usuarios = await db.UsuariosApp
                .Where(u => u.ClienteId == clienteId)
                .OrderBy(u => u.Login)
                .ToListAsync();

            var resp = usuarios.Select(u => new
            {
                u.Id,
                u.Login,
                u.CodigoTipo,
                admin  = Permissoes.EhAdmin(u),
                secoes = Permissoes.SecoesEfetivas(u).ToArray()
            });
            return Results.Ok(resp);
        }).RequireAuthorization();

        // Define as secoes liberadas de um usuario (nao-admin). Admins veem tudo por padrao.
        app.MapPut("/admin/usuarios/{id:int}/permissoes", async (
            int id, SetPermissoesDto dto, ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();
            var clienteId = int.Parse(user.FindFirstValue("cliente_id")!);

            var alvo = await db.UsuariosApp.FirstOrDefaultAsync(u => u.Id == id && u.ClienteId == clienteId);
            if (alvo is null) return Results.NotFound();

            // Normaliza (aceita so secoes validas) e grava como CSV; vazio => null (nada liberado)
            var validas = Permissoes.ParseSecoes(string.Join(',', dto.Secoes ?? Array.Empty<string>()));
            alvo.SecoesPermitidas = validas.Count > 0 ? string.Join(',', validas) : null;
            await db.SaveChangesAsync();

            return Results.Ok(new { alvo.Id, alvo.Login, secoes = Permissoes.SecoesEfetivas(alvo).ToArray() });
        }).RequireAuthorization();
    }

    // Relê o tipo do usuário no banco (não confia no claim 'admin', que pode estar obsoleto por até 8h)
    private static async Task<bool> EhAdminAtual(ClaimsPrincipal user, AppDbContext db)
    {
        if (!int.TryParse(user.FindFirstValue("usuario_id"), out var uid)) return false;
        var tipo = await db.UsuariosApp.Where(u => u.Id == uid).Select(u => u.CodigoTipo).FirstOrDefaultAsync();
        return tipo == Permissoes.TipoAdministrador;
    }
}
