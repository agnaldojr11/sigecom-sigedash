using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SigeDash.Central.Migrations
{
    /// <inheritdoc />
    public partial class LimiteGerenciadoCentral : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "LimiteAtualizadoEm",
                table: "Clientes",
                type: "timestamp with time zone",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "LimiteGerenciadoCentral",
                table: "Clientes",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "LimitePor",
                table: "Clientes",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "LimiteAtualizadoEm",
                table: "Clientes");

            migrationBuilder.DropColumn(
                name: "LimiteGerenciadoCentral",
                table: "Clientes");

            migrationBuilder.DropColumn(
                name: "LimitePor",
                table: "Clientes");
        }
    }
}
