using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SigeDash.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddLimiteDispositivos : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<int>(
                name: "LimiteDispositivos",
                table: "Clientes",
                type: "integer",
                nullable: false,
                defaultValue: 0);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "LimiteDispositivos",
                table: "Clientes");
        }
    }
}
