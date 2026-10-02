defmodule Platform.Database.Repo.Migrations.AddUserToOrders do
  use Ecto.Migration

  def change do
    # who made the order; null for orders made by the system (and old ones)
    alter table(:orders) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:orders, [:user_id])
  end
end
