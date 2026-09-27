defmodule Platform.Database.Repo.Migrations.AddOban do
  use Ecto.Migration

  # Oban's tables: the jobs (oban_jobs) and the cluster's leader (oban_peers).
  # A later Oban release that needs newer tables comes with its own version:
  # add a migration calling Oban.Migration.up(version: N).
  def up, do: Oban.Migration.up(version: 14)
  def down, do: Oban.Migration.down(version: 1)
end
