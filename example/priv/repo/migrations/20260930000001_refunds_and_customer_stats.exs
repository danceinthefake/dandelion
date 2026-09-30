defmodule Platform.Database.Repo.Migrations.RefundsAndCustomerStats do
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
  end

  def down do
    drop table(:customer_stats)
    drop constraint(:orders, :status_is_known)

    create constraint(:orders, :status_is_known,
             check: "status IN ('pending', 'paid', 'shipped', 'cancelled')"
           )
  end
end
