defmodule Platform.Database.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :text, null: false
      add :password_hash, :text, null: false
      add :role, :text, null: false, default: "customer"
      timestamps(type: :utc_datetime_usec)
    end

    # emails are stored lower-case, so a plain unique index is enough
    create unique_index(:users, [:email])
    create constraint(:users, :role_is_known, check: "role IN ('customer', 'admin')")
  end
end
