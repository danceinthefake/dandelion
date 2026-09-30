defmodule Platform.Database.Repo.Migrations.Events do
  use Ecto.Migration

  def up do
    # payments can refund an order
    drop constraint(:orders, :status_is_known)

    create constraint(:orders, :status_is_known,
             check: "status IN ('pending', 'paid', 'shipped', 'cancelled', 'refunded')"
           )

    # written by the order.created subscriber
    create table(:customer_stats, primary_key: false) do
      add :customer_email, :text, primary_key: true
      add :orders_count, :integer, null: false
      timestamps(type: :utc_datetime_usec, inserted_at: false)
    end

    # Platform.Queue.Ordered asks "is an earlier job of this key unfinished?"
    # on every run; this keeps that cheap.
    create index(:oban_jobs, ["(meta->>'ordered_key')", :id],
             where:
               "state IN ('available', 'scheduled', 'executing', 'retryable') AND meta ? 'ordered_key'",
             name: :oban_jobs_ordered_key_index
           )
  end

  def down do
    drop index(:oban_jobs, [], name: :oban_jobs_ordered_key_index)
    drop table(:customer_stats)
    drop constraint(:orders, :status_is_known)

    create constraint(:orders, :status_is_known,
             check: "status IN ('pending', 'paid', 'shipped', 'cancelled')"
           )
  end
end
