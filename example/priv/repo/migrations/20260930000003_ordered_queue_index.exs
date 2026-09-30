defmodule Platform.Database.Repo.Migrations.OrderedQueueIndex do
  use Ecto.Migration

  # The index Dandelion.Queue.Ordered asks through on every job run.
  def up, do: Dandelion.Migration.up()
  def down, do: Dandelion.Migration.down()
end
