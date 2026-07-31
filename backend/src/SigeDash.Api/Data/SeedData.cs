using SigeDash.Api.Modelos;
using SigeDash.Api.Seguranca;

namespace SigeDash.Api.Data;

/// <summary>
/// Seed de DESENVOLVIMENTO (roda so em Development, quando o banco esta vazio).
/// Cria o cliente "5 Estrelas", a loja (empresa 1) e um usuario ADMIN nativo para testes.
/// Em producao os usuarios sao nativos, criados pelo ADM da empresa (senha BCrypt).
/// </summary>
public static class SeedData
{
    // chave_api de teste usada pelo agente (header X-SigeDash-Key)
    public const string ChaveApiTeste = "TESTE-5ESTRELAS-0001";

    public static void Seed(AppDbContext db)
    {
        if (db.Clientes.Any()) return; // ja semeado

        var cliente = new Cliente
        {
            Nome = "5 Estrelas",
            ChaveApi = ChaveApiTeste,
            Ativo = true,
            Lojas = new List<Loja>
            {
                new Loja { CodigoEmpresa = 1, Nome = "Matriz" }
            }
        };
        db.Clientes.Add(cliente);
        db.SaveChanges();

        // Admin de DEV (login: admin / senha: admin123). Sem troca obrigatoria para facilitar o dev.
        db.UsuariosApp.Add(new UsuarioApp
        {
            ClienteId          = cliente.Id,
            Login              = "admin",
            NomeExibicao       = "Administrador (dev)",
            SenhaHash          = Senhas.Hash("admin123"),
            EhAdmin            = true,
            Ativo              = true,
            PrecisaTrocarSenha = false,
            CriadoEm           = DateTime.UtcNow
        });
        db.SaveChanges();
    }
}
