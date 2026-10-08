defmodule Platform.Database.Repo.Migrations.CreateStoredFiles do
  use Ecto.Migration

  def change do
    # What a file is. Its bytes are in the uploads directory, under `storage_key`
    # (Dandelion.Storage.Local); the row is what says whose it is.
    create table(:stored_files) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :filename, :text, null: false
      add :content_type, :text, null: false
      add :size, :bigint, null: false
      add :sha256, :text, null: false
      add :storage_key, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:stored_files, [:storage_key])
    create index(:stored_files, [:user_id])
  end
end
