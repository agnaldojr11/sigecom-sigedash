using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SigeDash.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddSessaoToken : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "SessaoToken",
                table: "UsuariosApp",
                type: "text",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SessaoToken",
                table: "UsuariosApp");
        }
    }
}
