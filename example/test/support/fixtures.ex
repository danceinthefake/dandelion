defmodule Shop.Fixtures do
  @moduledoc "Test helpers that create data. ≈ a Go `newTestOrder(t)` helper."

  alias Shop.Models.Order
  alias Shop.Repo
  alias Shop.Services.OrderService

  def order_params(overrides \\ %{}) do
    Map.merge(
      %{
        "customer_email" => "sari@example.com",
        "items" => [
          %{"sku" => "TEA-01", "quantity" => 2, "price_cents" => 1500},
          %{"sku" => "CUP-02", "quantity" => 1, "price_cents" => 4000}
        ]
      },
      overrides
    )
  end

  @doc "An order in the database, optionally in another status or with another creation time."
  def order_fixture(opts \\ []) do
    {:ok, order} = OrderService.create(order_params())

    order
    |> Ecto.Changeset.change(Keyword.take(opts, [:status, :inserted_at]))
    |> Repo.update!()
    |> then(&Repo.get!(Order, &1.id))
    |> Repo.preload(:items)
  end
end
