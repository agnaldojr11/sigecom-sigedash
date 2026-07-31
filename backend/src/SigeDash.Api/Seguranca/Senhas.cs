using System.Text.RegularExpressions;

namespace SigeDash.Api.Seguranca;

/// <summary>Hashing (BCrypt) e politica de senha do SigeDash.</summary>
public static class Senhas
{
    public const int TamanhoMinimo = 8;

    /// <summary>Gera o hash BCrypt (work factor 12).</summary>
    public static string Hash(string senha) => BCrypt.Net.BCrypt.HashPassword(senha, workFactor: 12);

    /// <summary>Confere a senha contra o hash BCrypt. Falha com seguranca se o hash for invalido/vazio.</summary>
    public static bool Conferir(string senha, string? hash)
    {
        if (string.IsNullOrEmpty(hash)) return false;
        try { return BCrypt.Net.BCrypt.Verify(senha, hash); }
        catch { return false; }
    }

    /// <summary>Valida a politica de senha. Retorna null se OK, ou a mensagem de erro.</summary>
    public static string? Validar(string? senha)
    {
        if (string.IsNullOrWhiteSpace(senha) || senha.Length < TamanhoMinimo)
            return $"A senha deve ter ao menos {TamanhoMinimo} caracteres.";
        if (!Regex.IsMatch(senha, "[A-Za-z]") || !Regex.IsMatch(senha, "[0-9]"))
            return "A senha deve conter letras e numeros.";
        return null;
    }

    /// <summary>Gera uma senha temporaria forte (CSPRNG) para primeiro acesso / reset.</summary>
    public static string GerarTemporaria(int tamanho = 12)
    {
        // Alfabeto sem caracteres ambiguos (0/O, 1/l/I) para facilitar digitacao.
        const string abc = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
        var bytes = System.Security.Cryptography.RandomNumberGenerator.GetBytes(tamanho);
        var chars = new char[tamanho];
        for (int i = 0; i < tamanho; i++) chars[i] = abc[bytes[i] % abc.Length];
        // Garante ao menos 1 letra e 1 numero (satisfaz a politica).
        chars[0] = 'S'; chars[^1] = '7';
        return new string(chars);
    }
}
