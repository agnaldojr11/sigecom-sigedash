using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SigeDash.Api.Migrations
{
    /// <inheritdoc />
    public partial class ReformaUsuariosNativos : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Modelo antigo (sincronizado do SIGECOM) -> modelo nativo do SigeDash.
            // Descarta os campos antigos (SHA1/CodigoTipo) em vez de renomear (evita carregar lixo).
            migrationBuilder.DropColumn(name: "SenhaApp",   table: "UsuariosApp");
            migrationBuilder.DropColumn(name: "CodigoTipo", table: "UsuariosApp");

            migrationBuilder.AddColumn<string>(
                name: "SenhaHash",
                table: "UsuariosApp",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<int>(
                name: "TentativasFalhas",
                table: "UsuariosApp",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<bool>(
                name: "Ativo",
                table: "UsuariosApp",
                type: "boolean",
                nullable: false,
                defaultValue: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "AtualizadoEm",
                table: "UsuariosApp",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "BloqueadoAte",
                table: "UsuariosApp",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "CriadoEm",
                table: "UsuariosApp",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AddColumn<bool>(
                name: "EhAdmin",
                table: "UsuariosApp",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "NomeExibicao",
                table: "UsuariosApp",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "PrecisaTrocarSenha",
                table: "UsuariosApp",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "TotpAtivado",
                table: "UsuariosApp",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "TotpSecret",
                table: "UsuariosApp",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<DateTime>(
                name: "UltimoLoginEm",
                table: "UsuariosApp",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Ativo",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "AtualizadoEm",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "BloqueadoAte",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "CriadoEm",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "EhAdmin",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "NomeExibicao",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "PrecisaTrocarSenha",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "TotpAtivado",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "TotpSecret",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "UltimoLoginEm",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(name: "SenhaHash",        table: "UsuariosApp");
            migrationBuilder.DropColumn(name: "TentativasFalhas", table: "UsuariosApp");

            migrationBuilder.AddColumn<string>(
                name: "SenhaApp",
                table: "UsuariosApp",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<int>(
                name: "CodigoTipo",
                table: "UsuariosApp",
                type: "integer",
                nullable: false,
                defaultValue: 0);
        }
    }
}
