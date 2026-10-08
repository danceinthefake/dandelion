defmodule Platform.Database.Repo.Migrations.AddAudit do
  use Ecto.Migration

  def up, do: Dandelion.Audit.Migration.up()
  def down, do: Dandelion.Audit.Migration.down()
end
