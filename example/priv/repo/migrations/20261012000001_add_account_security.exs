defmodule Platform.Database.Repo.Migrations.AddAccountSecurity do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # when the owner of the address showed they could read mail sent to it; nil until then
      add :email_confirmed_at, :utc_datetime_usec
    end

    # One-time links in emails (a password reset, an address confirmation). Only a hash of the
    # secret is kept: a copy of this table is not a set of working links.
    create table(:user_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :text, null: false
      add :token_hash, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:user_tokens, [:token_hash])
    create index(:user_tokens, [:user_id, :kind])
    create constraint(:user_tokens, :kind_is_known, check: "kind IN ('reset', 'confirm')")

    # Failed logins per email address typed — whether or not an account has that address, so
    # that a locked account and an address nobody has look the same from outside.
    create table(:login_throttle, primary_key: false) do
      add :email, :text, primary_key: true
      add :failures, :integer, null: false, default: 0
      add :locked_until, :utc_datetime_usec
      add :updated_at, :utc_datetime_usec, null: false
    end
  end
end
