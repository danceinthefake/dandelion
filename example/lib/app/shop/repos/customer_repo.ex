defmodule Platform.Database.Repos.CustomerRepo do
  @moduledoc "Per-customer numbers (`customer_stats`). ≈ `repo/customers.go`."
  alias Platform.Database.Repo

  @doc "Sets the customer's order count to the number of orders they have."
  @spec refresh_orders_count(String.t()) :: :ok
  def refresh_orders_count(email) do
    Repo.query!(
      """
      INSERT INTO customer_stats (customer_email, orders_count, updated_at)
      SELECT $1, count(*), now() FROM orders WHERE customer_email = $1
      ON CONFLICT (customer_email)
      DO UPDATE SET orders_count = EXCLUDED.orders_count, updated_at = EXCLUDED.updated_at
      """,
      [email]
    )

    :ok
  end

  @doc "The customer's order count, 0 if unknown."
  @spec orders_count(String.t()) :: non_neg_integer()
  def orders_count(email) do
    case Repo.query!("SELECT orders_count FROM customer_stats WHERE customer_email = $1", [email]) do
      %{rows: [[n]]} -> n
      _ -> 0
    end
  end
end
