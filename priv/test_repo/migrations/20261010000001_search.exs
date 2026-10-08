defmodule Dandelion.TestRepo.Migrations.Search do
  use Ecto.Migration

  def up do
    Dandelion.Search.Migration.up()

    create table(:search_items) do
      add :title, :text, null: false
      add :body, :text
    end

    Dandelion.Search.Migration.add_index(:search_items, [title: :a, body: :b], fuzzy: :title)
  end

  def down do
    Dandelion.Search.Migration.drop_index(:search_items, fuzzy: :title)
    drop table(:search_items)
    Dandelion.Search.Migration.down()
  end
end
