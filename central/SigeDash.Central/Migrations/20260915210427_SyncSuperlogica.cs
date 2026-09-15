using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SigeDash.Central.Migrations
{
    /// <inheritdoc />
    public partial class SyncSuperlogica : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTime>(
                name: "SincronizadoSuperlogicaEm",
                table: "Clientes",
                type: "timestamp with time zone",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SincronizadoSuperlogicaEm",
                table: "Clientes");
        }
    }
}
