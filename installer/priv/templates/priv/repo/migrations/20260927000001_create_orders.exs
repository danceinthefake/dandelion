defmodule Shop.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  # ≈ a golang-migrate / goose "up" file. `mix ecto.migrate` runs it,
  # `mix ecto.rollback` undoes it (Ecto derives the "down" from `create`).
  def change do
    create table(:orders) do
      add :customer_email, :text, null: false
      add :status, :text, null: false, default: "pending"
      add :total_cents, :bigint, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:orders, :status_is_known,
             check: "status IN ('pending', 'paid', 'shipped', 'cancelled')"
           )

    create index(:orders, [:status, :inserted_at])

    create table(:order_items) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :sku, :text, null: false
      add :quantity, :integer, null: false
      add :price_cents, :bigint, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:order_items, :quantity_is_positive, check: "quantity > 0")
    create constraint(:order_items, :price_is_not_negative, check: "price_cents >= 0")
    create index(:order_items, [:order_id])
  end
end
