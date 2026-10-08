defmodule Platform.Database.Repo.Migrations.AddFlags do
  use Ecto.Migration

  def up, do: Dandelion.Flags.Migration.up()
  def down, do: Dandelion.Flags.Migration.down()
end
