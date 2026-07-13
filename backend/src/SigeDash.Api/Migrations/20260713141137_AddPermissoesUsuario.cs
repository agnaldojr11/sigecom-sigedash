using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SigeDash.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddPermissoesUsuario : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "CodigoTipo",
                table: "UsuariosApp",
                type: "integer",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<string>(
                name: "SecoesPermitidas",
                table: "UsuariosApp",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "CodigoTipo",
                table: "UsuariosApp");

            migrationBuilder.DropColumn(
                name: "SecoesPermitidas",
                table: "UsuariosApp");
        }
    }
}
