defmodule Platform.Database.Repo.Migrations.CreateWebhookEndpoints do
  use Ecto.Migration

  def change do
    create table(:webhook_endpoints) do
      add :url, :text, null: false
      # signs what we send (Dandelion.Webhook); the receiver has the same one
      add :secret, :text, null: false
      add :events, {:array, :text}, null: false, default: []
      add :active, :boolean, null: false, default: true
      timestamps(type: :utc_datetime_usec)
    end

    create index(:webhook_endpoints, [:active])
  end
end
