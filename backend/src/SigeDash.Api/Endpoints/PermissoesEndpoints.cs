using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using SigeDash.Api.Data;
using SigeDash.Api.Modelos;
using SigeDash.Api.Seguranca;

namespace SigeDash.Api.Endpoints;

public record SetPermissoesDto(string[] Secoes);
public record CriarUsuarioDto(string Login, string? NomeExibicao, string? Senha, bool EhAdmin, string[]? Secoes);
public record EditarUsuarioDto(string? NomeExibicao, bool? EhAdmin, bool? Ativo);

/// <summary>
/// Gestao de usuarios e permissoes pelo ADMIN da empresa (UsuarioApp.EhAdmin), verificado no banco.
/// Tudo escopado ao cliente do admin logado. Usuarios sao nativos (senha BCrypt); o admin cria,
/// edita, reseta senha, ativa/desativa e define as secoes de cada um.
/// </summary>
public static class PermissoesEndpoints
{
    public static void MapPermissoes(this IEndpointRouteBuilder app)
    {
        // Lista os usuarios do cliente (para a tela de gestao)
        app.MapGet("/admin/usuarios", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();
            var clienteId = ClienteId(user);

            var usuarios = await db.UsuariosApp
                .Where(u => u.ClienteId == clienteId)
                .OrderBy(u => u.Login)
                .ToListAsync();

            var resp = usuarios.Select(u => new
            {
                u.Id,
                u.Login,
                u.NomeExibicao,
                admin  = u.EhAdmin,
                u.Ativo,
                u.PrecisaTrocarSenha,
                u.TotpAtivado,
                u.UltimoLoginEm,
                secoes = Permissoes.SecoesEfetivas(u).ToArray()
            });
            return Results.Ok(resp);
        }).RequireAuthorization();

        // Cria um novo usuario. Retorna a senha temporaria UMA vez (para o admin repassar).
        app.MapPost("/admin/usuarios", async (CriarUsuarioDto dto, ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();
            var clienteId = ClienteId(user);

            var login = (dto.Login ?? "").Trim();
            if (login.Length == 0) return Bad("Informe o login.");
            if (await db.UsuariosApp.AnyAsync(u => u.ClienteId == clienteId && u.Login == login))
                return Results.Conflict(new { erro = $"Ja existe um usuario '{login}'." });

            // Limite de dispositivos/seats do plano (0 = ilimitado). Usuario novo nasce ativo => consome 1 vaga.
            var limite = await LimitePlano(db, clienteId);
            if (limite > 0)
            {
                var ativos = await db.UsuariosApp.CountAsync(u => u.ClienteId == clienteId && u.Ativo);
                if (ativos >= limite)
                    return Results.Json(new { erro = $"Limite de dispositivos do plano atingido ({limite}). Contate a SistemasBr para liberar mais." },
                                        statusCode: StatusCodes.Status409Conflict);
            }

            // Senha: se o admin informar, valida a politica; senao gera uma temporaria forte.
            string senhaPlano;
            if (string.IsNullOrWhiteSpace(dto.Senha)) senhaPlano = Senhas.GerarTemporaria();
            else { var e = Senhas.Validar(dto.Senha); if (e is not null) return Bad(e); senhaPlano = dto.Senha!; }

            var secoes = Permissoes.ParseSecoes(string.Join(',', dto.Secoes ?? Array.Empty<string>()));
            var novo = new UsuarioApp
            {
                ClienteId          = clienteId,
                Login              = login,
                NomeExibicao       = string.IsNullOrWhiteSpace(dto.NomeExibicao) ? null : dto.NomeExibicao!.Trim(),
                SenhaHash          = Senhas.Hash(senhaPlano),
                EhAdmin            = dto.EhAdmin,
                Ativo              = true,
                PrecisaTrocarSenha = true,   // troca obrigatoria no 1o acesso
                SecoesPermitidas   = (!dto.EhAdmin && secoes.Count > 0) ? string.Join(',', secoes) : null,
                CriadoEm           = DateTime.UtcNow
            };
            db.UsuariosApp.Add(novo);
            await db.SaveChangesAsync();
            return Results.Ok(new { novo.Id, novo.Login, senhaTemporaria = senhaPlano });
        }).RequireAuthorization();

        // Edita nome/admin/ativo. Nao permite o admin rebaixar/desativar a si mesmo.
        app.MapPut("/admin/usuarios/{id:int}", async (
            int id, EditarUsuarioDto dto, ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();
            var clienteId = ClienteId(user);
            var alvo = await db.UsuariosApp.FirstOrDefaultAsync(u => u.Id == id && u.ClienteId == clienteId);
            if (alvo is null) return Results.NotFound();

            var euId = UsuarioId(user);
            if (alvo.Id == euId && (dto.EhAdmin == false || dto.Ativo == false))
                return Bad("Voce nao pode remover seu proprio acesso de administrador nem se desativar.");

            // Reativar um usuario consome 1 vaga do plano — respeita o limite de dispositivos.
            if (dto.Ativo == true && alvo.Ativo == false)
            {
                var limite = await LimitePlano(db, clienteId);
                if (limite > 0)
                {
                    var ativos = await db.UsuariosApp.CountAsync(u => u.ClienteId == clienteId && u.Ativo);
                    if (ativos >= limite)
                        return Bad($"Limite de dispositivos do plano atingido ({limite}). Desative outro usuario ou contate a SistemasBr.");
                }
            }

            if (dto.NomeExibicao is not null) alvo.NomeExibicao = string.IsNullOrWhiteSpace(dto.NomeExibicao) ? null : dto.NomeExibicao.Trim();
            if (dto.EhAdmin is { } adm) alvo.EhAdmin = adm;
            if (dto.Ativo  is { } at)  alvo.Ativo   = at;
            alvo.AtualizadoEm = DateTime.UtcNow;
            await db.SaveChangesAsync();
            return Results.Ok(new { alvo.Id, alvo.Login, admin = alvo.EhAdmin, alvo.Ativo });
        }).RequireAuthorization();

        // Reseta a senha: gera temporaria, exige troca no proximo login. Retorna a senha UMA vez.
        app.MapPost("/admin/usuarios/{id:int}/resetar-senha", async (
            int id, ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();
            var clienteId = ClienteId(user);
            var alvo = await db.UsuariosApp.FirstOrDefaultAsync(u => u.Id == id && u.ClienteId == clienteId);
            if (alvo is null) return Results.NotFound();

            var senha = Senhas.GerarTemporaria();
            alvo.SenhaHash          = Senhas.Hash(senha);
            alvo.PrecisaTrocarSenha = true;
            alvo.BloqueadoAte       = null;
            alvo.TentativasFalhas   = 0;
            alvo.SessaoToken        = null; // derruba sessoes ativas
            alvo.AtualizadoEm       = DateTime.UtcNow;
            await db.SaveChangesAsync();
            return Results.Ok(new { alvo.Id, alvo.Login, senhaTemporaria = senha });
        }).RequireAuthorization();

        // Exclui um usuario (nao permite excluir a si mesmo).
        app.MapDelete("/admin/usuarios/{id:int}", async (int id, ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();
            var clienteId = ClienteId(user);
            if (id == UsuarioId(user)) return Bad("Voce nao pode excluir o proprio usuario.");
            var alvo = await db.UsuariosApp.FirstOrDefaultAsync(u => u.Id == id && u.ClienteId == clienteId);
            if (alvo is null) return Results.NotFound();
            db.UsuariosApp.Remove(alvo);
            await db.SaveChangesAsync();
            return Results.Ok(new { removido = alvo.Login });
        }).RequireAuthorization();

        // Define as secoes liberadas de um usuario (nao-admin). Admins veem tudo por padrao.
        app.MapPut("/admin/usuarios/{id:int}/permissoes", async (
            int id, SetPermissoesDto dto, ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();
            var clienteId = ClienteId(user);
            var alvo = await db.UsuariosApp.FirstOrDefaultAsync(u => u.Id == id && u.ClienteId == clienteId);
            if (alvo is null) return Results.NotFound();

            var validas = Permissoes.ParseSecoes(string.Join(',', dto.Secoes ?? Array.Empty<string>()));
            alvo.SecoesPermitidas = validas.Count > 0 ? string.Join(',', validas) : null;
            alvo.AtualizadoEm = DateTime.UtcNow;
            await db.SaveChangesAsync();
            return Results.Ok(new { alvo.Id, alvo.Login, secoes = Permissoes.SecoesEfetivas(alvo).ToArray() });
        }).RequireAuthorization();

        // Plano do cliente: limite de dispositivos (seats) e quantos usuarios ativos ha.
        // O admin do cliente SO visualiza (nao altera o limite — isso e da SistemasBr).
        app.MapGet("/admin/plano", async (ClaimsPrincipal user, AppDbContext db) =>
        {
            if (!await EhAdminAtual(user, db)) return Results.Forbid();
            var clienteId = ClienteId(user);
            var limite = await LimitePlano(db, clienteId);
            var ativos = await db.UsuariosApp.CountAsync(u => u.ClienteId == clienteId && u.Ativo);
            return Results.Ok(new
            {
                limiteDispositivos = limite,
                usuariosAtivos     = ativos,
                ilimitado          = limite <= 0,
                disponivel         = limite <= 0 ? (int?)null : Math.Max(0, limite - ativos)
            });
        }).RequireAuthorization();
    }

    // Limite de dispositivos/seats do plano do cliente (0 = ilimitado).
    private static async Task<int> LimitePlano(AppDbContext db, int clienteId)
        => await db.Clientes.Where(c => c.Id == clienteId).Select(c => c.LimiteDispositivos).FirstOrDefaultAsync();

    private static IResult Bad(string erro) => Results.Json(new { erro }, statusCode: StatusCodes.Status400BadRequest);
    private static int ClienteId(ClaimsPrincipal u) => int.Parse(u.FindFirstValue("cliente_id")!);
    private static int UsuarioId(ClaimsPrincipal u) => int.TryParse(u.FindFirstValue("usuario_id"), out var v) ? v : 0;

    // Rele o tipo do usuario no banco (nao confia no claim 'admin', que pode estar obsoleto por ate 8h)
    private static async Task<bool> EhAdminAtual(ClaimsPrincipal user, AppDbContext db)
    {
        if (!int.TryParse(user.FindFirstValue("usuario_id"), out var uid)) return false;
        var u = await db.UsuariosApp.Where(x => x.Id == uid).Select(x => new { x.EhAdmin, x.Ativo }).FirstOrDefaultAsync();
        return u is not null && u.Ativo && u.EhAdmin;
    }
}
