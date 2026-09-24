using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SigeDash.Central.Migrations
{
    /// <inheritdoc />
    public partial class GestaoUsuariosPainel : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "Ativo",
                table: "UsuariosPainel",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<DateTime>(
                name: "CriadoEm",
                table: "UsuariosPainel",
                type: "timestamp with time zone",
                nullable: false,
                defaultValue: new DateTime(1, 1, 1, 0, 0, 0, 0, DateTimeKind.Unspecified));

            migrationBuilder.AddColumn<string>(
                name: "CriadoPor",
                table: "UsuariosPainel",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Papel",
                table: "UsuariosPainel",
                type: "text",
                nullable: false,
                defaultValue: "");

            // Backfill: os usuários que já existem hoje são o(s) admin(s) semeado(s) pela env —
            // garante que continuem admin, ativos e com data de criação válida.
            migrationBuilder.Sql(
                "UPDATE \"UsuariosPainel\" SET \"Papel\" = 'admin', \"Ativo\" = true, " +
                "\"CriadoEm\" = NOW() WHERE \"Papel\" = '';");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Ativo",
                table: "UsuariosPainel");

            migrationBuilder.DropColumn(
                name: "CriadoEm",
                table: "UsuariosPainel");

            migrationBuilder.DropColumn(
                name: "CriadoPor",
                table: "UsuariosPainel");

            migrationBuilder.DropColumn(
                name: "Papel",
                table: "UsuariosPainel");
        }
    }
}
