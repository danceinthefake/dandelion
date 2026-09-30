defmodule Dandelion.TestRepo.Migrations.Dandelion do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 14)
    Dandelion.Migration.up()
  end

  def down do
    Dandelion.Migration.down()
    Oban.Migration.down(version: 1)
  end
end
