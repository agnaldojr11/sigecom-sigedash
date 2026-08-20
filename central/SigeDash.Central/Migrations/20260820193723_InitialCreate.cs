using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace SigeDash.Central.Migrations
{
    /// <inheritdoc />
    public partial class InitialCreate : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Clientes",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Nome = table.Column<string>(type: "text", nullable: false),
                    Cnpj = table.Column<string>(type: "text", nullable: true),
                    ChaveTelemetria = table.Column<string>(type: "text", nullable: false),
                    LimiteDispositivos = table.Column<int>(type: "integer", nullable: false),
                    Ativo = table.Column<bool>(type: "boolean", nullable: false),
                    CriadoEm = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Observacao = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Clientes", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "HeartbeatHistorico",
                columns: table => new
                {
                    Id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    ClienteId = table.Column<int>(type: "integer", nullable: false),
                    Ts = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Versao = table.Column<string>(type: "text", nullable: true),
                    UsuariosAtivos = table.Column<int>(type: "integer", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_HeartbeatHistorico", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "UsuariosPainel",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    Login = table.Column<string>(type: "text", nullable: false),
                    SenhaHash = table.Column<string>(type: "text", nullable: false),
                    UltimoLoginEm = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_UsuariosPainel", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "Heartbeats",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    ClienteId = table.Column<int>(type: "integer", nullable: false),
                    RecebidoEm = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    Versao = table.Column<string>(type: "text", nullable: true),
                    UptimeSeg = table.Column<long>(type: "bigint", nullable: false),
                    UsuariosAtivos = table.Column<int>(type: "integer", nullable: false),
                    LimiteDispositivos = table.Column<int>(type: "integer", nullable: false),
                    Os = table.Column<string>(type: "text", nullable: true),
                    StatusBackend = table.Column<string>(type: "text", nullable: true),
                    StatusPg = table.Column<string>(type: "text", nullable: true),
                    Ip = table.Column<string>(type: "text", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Heartbeats", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Heartbeats_Clientes_ClienteId",
                        column: x => x.ClienteId,
                        principalTable: "Clientes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "IndicadoresSaude",
                columns: table => new
                {
                    Id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    ClienteId = table.Column<int>(type: "integer", nullable: false),
                    Handle = table.Column<string>(type: "text", nullable: false),
                    UltimoSucesso = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    UltimoErro = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    Status = table.Column<string>(type: "text", nullable: false),
                    Mensagem = table.Column<string>(type: "text", nullable: true),
                    AtualizadoEm = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_IndicadoresSaude", x => x.Id);
                    table.ForeignKey(
                        name: "FK_IndicadoresSaude_Clientes_ClienteId",
                        column: x => x.ClienteId,
                        principalTable: "Clientes",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Clientes_ChaveTelemetria",
                table: "Clientes",
                column: "ChaveTelemetria",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Clientes_Nome",
                table: "Clientes",
                column: "Nome");

            migrationBuilder.CreateIndex(
                name: "IX_HeartbeatHistorico_ClienteId_Ts",
                table: "HeartbeatHistorico",
                columns: new[] { "ClienteId", "Ts" });

            migrationBuilder.CreateIndex(
                name: "IX_Heartbeats_ClienteId",
                table: "Heartbeats",
                column: "ClienteId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_IndicadoresSaude_ClienteId_Handle",
                table: "IndicadoresSaude",
                columns: new[] { "ClienteId", "Handle" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_UsuariosPainel_Login",
                table: "UsuariosPainel",
                column: "Login",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "HeartbeatHistorico");

            migrationBuilder.DropTable(
                name: "Heartbeats");

            migrationBuilder.DropTable(
                name: "IndicadoresSaude");

            migrationBuilder.DropTable(
                name: "UsuariosPainel");

            migrationBuilder.DropTable(
                name: "Clientes");
        }
    }
}
