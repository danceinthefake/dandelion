defmodule Platform.Database.Repo.Migrations.CreateOutgoingEmails do
  use Ecto.Migration

  def change do
    # Every email we mean to send: written before it is sent, marked after. The unique
    # `dedupe_key` is what stops a retried job from mailing the same thing twice.
    create table(:outgoing_emails) do
      add :dedupe_key, :text, null: false
      add :kind, :text, null: false
      add :to_address, :text, null: false
      add :subject, :text, null: false
      add :body, :text, null: false
      add :status, :text, null: false, default: "queued"
      add :attempts, :integer, null: false, default: 0
      add :last_error, :text
      add :sent_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:outgoing_emails, [:dedupe_key])
    create index(:outgoing_emails, [:status, :id])

    create constraint(:outgoing_emails, :status_is_known,
             check: "status IN ('queued', 'sent', 'failed')"
           )
  end
end
