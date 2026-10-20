using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace SigeDash.Central.Migrations
{
    /// <inheritdoc />
    public partial class RelatoriosInstalacao : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "RelatoriosInstalacao",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    RecebidoEm = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ClienteId = table.Column<int>(type: "integer", nullable: true),
                    Tipo = table.Column<string>(type: "text", nullable: false),
                    Nome = table.Column<string>(type: "text", nullable: false),
                    Cnpj = table.Column<string>(type: "text", nullable: true),
                    Versao = table.Column<string>(type: "text", nullable: true),
                    Os = table.Column<string>(type: "text", nullable: true),
                    Maquina = table.Column<string>(type: "text", nullable: true),
                    Status = table.Column<string>(type: "text", nullable: false),
                    Etapa = table.Column<string>(type: "text", nullable: true),
                    Mensagem = table.Column<string>(type: "text", nullable: true),
                    Avisos = table.Column<string>(type: "text", nullable: true),
                    Url = table.Column<string>(type: "text", nullable: true),
                    DuracaoSeg = table.Column<int>(type: "integer", nullable: true),
                    Bloqueios = table.Column<int>(type: "integer", nullable: false),
                    Verificacoes = table.Column<string>(type: "text", nullable: true),
                    Log = table.Column<string>(type: "text", nullable: true),
                    Ip = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_RelatoriosInstalacao", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_RelatoriosInstalacao_ClienteId",
                table: "RelatoriosInstalacao",
                column: "ClienteId");

            migrationBuilder.CreateIndex(
                name: "IX_RelatoriosInstalacao_RecebidoEm",
                table: "RelatoriosInstalacao",
                column: "RecebidoEm");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "RelatoriosInstalacao");
        }
    }
}
