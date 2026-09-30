defmodule Platform.Database.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products, primary_key: false) do
      add :sku, :text, primary_key: true
      add :name, :text, null: false
      add :price_cents, :bigint, null: false
      timestamps(type: :utc_datetime_usec, inserted_at: false)
    end

    create constraint(:products, :price_is_not_negative, check: "price_cents >= 0")
  end
end
