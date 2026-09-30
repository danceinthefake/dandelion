defmodule Dandelion.Migration do
  @moduledoc """
  The database changes dandelion needs, called from your own migration — the
  way `Oban.Migration` is:

      defmodule MyApp.Repo.Migrations.AddDandelion do
        use Ecto.Migration

        def up, do: Dandelion.Migration.up()
        def down, do: Dandelion.Migration.down()
      end

  Run it **after** the Oban migration: it adds an index to `oban_jobs` for
  `Dandelion.Queue.Ordered`.
  """
  import Ecto.Migration

  @index :oban_jobs_ordered_key_index

  @doc "Adds the index `Dandelion.Queue.Ordered` asks through on every job run."
  def up do
    create_if_not_exists(
      index(:oban_jobs, ["(meta->>'ordered_key')", :id],
        where:
          "state IN ('available', 'scheduled', 'executing', 'retryable') AND meta ? 'ordered_key'",
        name: @index
      )
    )
  end

  @doc "Removes what `up/0` added."
  def down do
    drop_if_exists(index(:oban_jobs, [], name: @index))
  end
end
