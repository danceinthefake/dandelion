defmodule App.Shop.Fixtures do
  @moduledoc "Test helpers that create data. ≈ a Go `newTestOrder(t)` helper."

  alias App.Shop.Models.Order
  alias App.Shop.Services.OrderService
  alias Platform.Database.Repo

  def order_params(overrides \\ %{}) do
    Map.merge(
      %{
        "customer_email" => "sari@example.com",
        "items" => [
          %{"sku" => "TEA-01", "quantity" => 2},
          %{"sku" => "CUP-02", "quantity" => 1}
        ]
      },
      overrides
    )
  end

  @doc "An order in the database, optionally in another status or with another creation time."
  def order_fixture(opts \\ []) do
    params =
      if email = opts[:email],
        do: order_params(%{"customer_email" => email}),
        else: order_params()

    {:ok, order} = OrderService.create(params)

    order
    |> Ecto.Changeset.change(Keyword.take(opts, [:status, :inserted_at]))
    |> Repo.update!()
    |> then(&Repo.get!(Order, &1.id))
    |> Repo.preload(:items)
  end

  @doc "A product in the database, under a SKU no other test uses."
  def product_fixture(attrs \\ %{}) do
    Repo.insert!(
      struct!(
        App.Shop.Models.Product,
        Map.merge(
          %{sku: "SKU-#{System.unique_integer([:positive])}", name: "Tea", price_cents: 1500},
          attrs
        )
      )
    )
  end
end
