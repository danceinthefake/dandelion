defmodule Platform.Database.Repo.Migrations.AddProductSearch do
  use Ecto.Migration

  def up do
    Dandelion.Search.Migration.up()

    alter table(:products) do
      add :description, :text
    end

    # `search` is kept up to date by Postgres itself (a generated column): a product is
    # searchable the moment it is committed. A match in the name outranks one in the text.
    Dandelion.Search.Migration.add_index(:products, [name: :a, description: :b], fuzzy: :name)
  end

  def down do
    Dandelion.Search.Migration.drop_index(:products, fuzzy: :name)

    alter table(:products) do
      remove :description
    end

    Dandelion.Search.Migration.down()
  end
end
