defmodule Dandelion.Flags.Migration do
  @moduledoc """
  The table `Dandelion.Flags` keeps its values in, called from your own migration:

      defmodule MyApp.Repo.Migrations.AddFlags do
        use Ecto.Migration

        def up, do: Dandelion.Flags.Migration.up()
        def down, do: Dandelion.Flags.Migration.down()
      end
  """
  import Ecto.Migration

  def up do
    create_if_not_exists table(:dandelion_flags, primary_key: false) do
      add(:key, :text, primary_key: true)
      add(:value, :jsonb, null: false)
      add(:updated_at, :utc_datetime_usec, null: false)
    end
  end

  def down, do: drop_if_exists(table(:dandelion_flags))
end
