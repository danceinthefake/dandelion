defmodule Platform.Database.Repo.Migrations.AddIdempotencyToOrders do
  use Ecto.Migration

  def change do
    # A client's retry key for creating an order, and a fingerprint of the request
    # it came with. Null for orders made without one.
    alter table(:orders) do
      add :idempotency_key, :text
      add :request_hash, :text
    end

    # One order per (customer, key). Nulls are distinct, so orders without a key
    # never clash. The index is what makes two retries racing safe.
    create unique_index(:orders, [:user_id, :idempotency_key])
  end
end
